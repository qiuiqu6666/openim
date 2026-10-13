package cn.gameshield.sdk;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.security.SecureRandom;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * GameShield Android SDK (核心引擎, 除安卓自带 org.json 外零依赖)
 *
 * 轻量原则: 全程仅 1 条调度线程(5s tick), 不额外起服务/不注册广播常驻;
 *           游戏无活动连接时自动休眠(0网络探针), 断点/切换事件本地回调+批量上报后台。
 *
 * 用法:
 *   GameShieldClient cli = new GameShieldClient("http://调度:9200", sdk_token, aes_key_hex);
 *   cli.setOnEvent((code,msg,node) -> ...);   // 可选: 事件回调(掉线/切换原因, 任意线程回调)
 *   cli.start();   // 拉 conf+节点列表, 本地起 127.0.0.1 代理端口(TCP/UDP)
 *
 * 接入方式(壳App改造游戏时二选一):
 *   A. 修改游戏内服务器地址为 127.0.0.1:localPort (需重打包, 常见于盾壳)
 *   B. 配套 VpnService 透明接管: 只劫持游戏目标IP段, 改写为本地端口 (推荐, 免改包)
 *
 * 协议与 node/index.js 完全一致:
 *   帧 = [1B type][4B BE len][payload]; DATA负载 = IV(12)+ct+tag(16) AES-256-GCM
 *   HELLO = {"v":1,"project_id":P,"port":X,"nonce":N,"auth":HmacSHA256(key,"P:X:N"),"sid":S}
 *   sid=本局游戏连接的稳定会话号(主/备通道与重挂复用), 仅源站网关用于跨节点会话锚定
 */
public class GameShieldClient {
    public static final byte T_HELLO = 1, T_DATA = 2, T_PING = 3, T_PONG = 4;

    /** 事件回调(与 shared/events.js 字典同码): start/sched_ok/sched_fail/node_down/rtt_bad/
     *  node_switch/backup_up/backup_promote/resume_ok/resume_fail/hello_reject/tunnel_err/
     *  udp_rebind/idle_enter/idle_exit/bulk_line/tunnel_eof/conn_storm/stop */
    public interface OnEvent { void onEvent(String code, String msg, String node); }

    /** ★第卅九轮回2: VPN 透明接管守护 —— 本机启用 VpnService 时, 所有"盾自己要出去"的 socket
     *  必须 VpnService.protect() 后再 connect, 否则隧道出网包会再次被 tun 捕获形成自环。
     *  由注入代理 GSProxyApp 在盾启动时挂上(GSVpnService.RUNNING.protect)。 */
    public interface SocketGuard { boolean protect(java.net.Socket s); }
    public static volatile SocketGuard GUARD;

    /** 当前盾接管的本机代理端口集合(conf ports 的键), 供透明接管做"按端口接管"判定 */
    public java.util.Set<Integer> rulePorts() { return ports.keySet(); }
    public java.util.Set<Integer> boundTcpPorts() {
        java.util.Set<Integer> result = new java.util.HashSet<>();
        for (ServerSocket socket : tcpListeners) if (!socket.isClosed()) result.add(socket.getLocalPort());
        return result;
    }

    private final String cpBase, token;
    private final byte[] aesKey;
    private int projectId, tunnelPort = 20000;
    private String protocol = "tcp";
    private final Map<Integer, Integer> ports = new HashMap<>();
    private volatile String nodeIp;
    private final java.util.List<String> ranked = java.util.Collections.synchronizedList(new java.util.ArrayList<String>());
    private final ExecutorService pool = Executors.newCachedThreadPool();
    private volatile boolean running;
    private final java.util.List<ServerSocket> tcpListeners = new java.util.concurrent.CopyOnWriteArrayList<>();
    private final java.util.List<Session> tcpSessions = new java.util.concurrent.CopyOnWriteArrayList<>();
    // ---- 事件/上报/轻量化 ----
    private volatile OnEvent listener;
    private final java.util.ArrayDeque<String> outbox = new java.util.ArrayDeque<>();  // 序列化的事件JSON
    private final java.util.concurrent.atomic.AtomicInteger activeSessions = new java.util.concurrent.atomic.AtomicInteger();
    private volatile boolean idle = true;
    private volatile int gapMax = 65536;             // 断口缓冲上限(默认64KB, 极省内存)
    // ★第卌二轮: 30s→60s。主隧建立排队放宽到50s(见 openTunnel), 旧窗口30s会被一次排队整段吃掉,
    //   误报 resume_fail 掐死游戏连接; 60s≈游戏 HTTP 层自身超时上限, 引擎不必抢在它前面判死。
    private volatile int resumeGraceMs = 60000;      // 断口重挂宽限期(第卅七轮10s→30s, 第卌二轮→60s)
    // 第卅九轮回3: 多会话并发重挂曾以~4次/秒打 /sdk/v1/nodes, 60s 内耗尽服务端30次限频后
    //   全池雪崩报 sched_fail(invalid)——调度请求全局节流 3s 一次, 失败事件同类 10s 去重。
    private volatile long lastNodesTry = 0;
    private volatile long lastSchedFailAt = 0;
    // ---- 第卌轮: 热更新专用单线通道 + 握手预算(根治"并发太多→反DDoS封自己IP→重进无法连接"自毁链) ----
    //   节点对"每个新TCP连接"(含测速探针!)按 IP 计数, 120/分钟/IP 即封300s。旧版风暴:
    //   断口重挂每会话≤4次/秒 + rankByRtt 每3s打全池8节点 = 不写一行HELLO也能封满。
    //   现在: ①所有出网连接共用滑窗预算 ②按端口钉节点(同端口所有并发连接同一条线跑完)
    //         ③会话下行超2MB判大流量(热更新)→ 关备镜像单线跑, 期间停探针误切。
    private final java.util.Map<String, java.util.ArrayDeque<Long>> helloWin = new java.util.HashMap<>();
    // ★第卌二轮: 预算 40→100/节点/分。旧值40=服务端120的"1/3自我阉割", 但游戏热更新天生40并发,
    //   主+备双隧=80 HELLO/分, 恒撞自设的40线 → 新连接排队20s超时 → 引擎 resume_fail 后 game.close()
    //   掐死游戏下载连接(实测一轮 resume_fail×47) → 游戏弹"下载异常重试" → 再风暴。服务端BAN是
    //   【每节点独立计数】, 四闸(钉线/30s节流/探针静默/预算闸)已在, 100=120再留20余量安全。
    private static final int HELLO_BUDGET_PER_NODE = 100;
    // ★第卌二轮: 高并发端口自动识别=大流量(热更新)特征 —— 旧版2MB/单会话字节阈值对
    //   "40路×每路几百KB的短连接并行下载"永不触发(bulk_line×0实锤), 镜像/探针照跑放大HELLO。
    private final java.util.Map<Integer, Integer> portConc = new java.util.concurrent.ConcurrentHashMap<>();
    private final java.util.Map<Integer, Long> bulkUntil = new java.util.concurrent.ConcurrentHashMap<>();
    private static final int BULK_PORT_CONC = 6;      // 同端口并发≥6路 → 判为下载口(业务长连口并发恒1-2)
    private static final long BULK_PORT_MS = 120000;  // 端口bulk态120s有效, 期间每路新连接自动续期
    private static final long IDLE_END_MS = 15000;    // 隧道EOF且双向静默>15s=上游正常收尾(keep-alive回收), 非节点故障
    // ★第卌三轮: 端口级并发熔断 —— 取证实锤"游戏进不去服时秒级狂重连": 6分钟堆出1120条网关会话,
    //   全部变成对源站游戏端口的fd占用(正常业务1-2路)。>64路=纯风暴, 拒新连接:
    //   对游戏本身也是保护(让它快速拿到连接失败而不是无限攒半死socket), 网关/源站/面板三方止血。
    // ★第52轮: bulk口(热更新/版本下载, 第卌二轮并发≥6判)豁免64线 —— 盾27实锤它误杀合法流量:
    //   HTTP更新器 keep-alive 池+并行分块天然几十~上百路, 第65路撞上熔闸后版本请求被自家SDK掐死 →
    //   「获取版本信息失败」无限重试 → 重连风暴在网关堆出496条会话(自伤死锁)。热更口天花板改与
    //   服务器 ip_conn_limit=256 线对齐(节点侧256线才是真fd兜底), 非热更业务口保持64线防风暴。
    private static final int PORT_MAX_CONC = 64;
    private static final int BULK_MAX_CONC = 256;
    private volatile long lastStormAt = 0;
    private final java.util.Map<Integer, String> portPin = new java.util.concurrent.ConcurrentHashMap<>();
    private final java.util.concurrent.atomic.AtomicInteger bulkSessions = new java.util.concurrent.atomic.AtomicInteger();
    private volatile long lastRankAt = 0;
    private static final String CLIENT_VER = "android/1.4.6";

    public GameShieldClient(String cpBase, String sdkToken, String aesKeyHex) {
        this.cpBase = cpBase.endsWith("/") ? cpBase.substring(0, cpBase.length() - 1) : cpBase;
        this.token = sdkToken;
        this.aesKey = hex(aesKeyHex);
    }
    public void setOnEvent(OnEvent l) { listener = l; }
    public void setPendingMax(int bytes) { if (bytes >= 4096) gapMax = bytes; }
    /** 断口重挂宽限期(秒, ≥10, 默认60): 全部节点瞬断时游戏 socket 保持等待的窗口 */
    public void setResumeGraceSec(int sec) { if (sec >= 10) resumeGraceMs = sec * 1000; }
    public boolean isIdle() { return idle; }

    /** 事件总线: 回调(任意线程) + android日志 + 上报队列(30s随调度线程批量POST) */
    void evt(String code, String msg, String node) {
        String n = node != null ? node : (nodeIp != null ? nodeIp : "");
        try {
            JSONObject j = new JSONObject();
            j.put("t", System.currentTimeMillis()).put("code", code)
             .put("msg", msg == null ? "" : msg.substring(0, Math.min(msg.length(), 480))).put("node", n);
            synchronized (outbox) {
                outbox.add(j.toString());
                while (outbox.size() > 200) outbox.pollFirst();   // 极端断网时不涨内存
            }
        } catch (Exception ignored) { }
        android.util.Log.i("GShield", "[" + code + "] " + msg + (n.isEmpty() ? "" : " @" + n));
        OnEvent l = listener;
        if (l != null) { try { l.onEvent(code, msg, n); } catch (Exception ignored) { } }
    }

    void flushReport() {
        java.util.ArrayList<String> batch = new java.util.ArrayList<>();
        synchronized (outbox) { while (!outbox.isEmpty() && batch.size() < 50) batch.add(outbox.pollFirst()); }
        if (batch.isEmpty()) return;
        try {
            JSONArray arr = new JSONArray();
            for (String s : batch) arr.put(new JSONObject(s));
            JSONObject body = new JSONObject();
            body.put("token", token).put("client", CLIENT_VER).put("events", arr);
            apiPost("/sdk/v1/log", body);
        } catch (Exception e) {
            synchronized (outbox) {                       // 送出失败回塞
                for (int i = batch.size() - 1; i >= 0; i--) outbox.addFirst(batch.get(i));
                while (outbox.size() > 200) outbox.pollFirst();
            }
        }
    }

    // ================= 生命周期 =================
    public void start() throws IOException {
        try {
        JSONObject conf = api("/sdk/v1/conf?token=" + token);
        if (conf.getInt("code") != 0) throw new IOException("conf: " + conf.optString("msg"));
        JSONObject d = conf.getJSONObject("data");
        projectId = d.getInt("project_id");
        protocol = d.optString("protocol", "tcp");
        tunnelPort = d.getInt("tunnel_port");
        JSONObject p = d.getJSONObject("ports");
        JSONArray keys = p.names();
        if (keys != null) for (int i = 0; i < keys.length(); i++) {
            String k = keys.getString(i);
            ports.put(Integer.parseInt(k), p.getInt(k));
        }
        } catch (JSONException e) { throw new IOException("conf-json: " + e); }
        refreshNodes();
        running = true;
        for (int lp : ports.keySet()) {
            if ("udp".equals(protocol) || protocol.equals("all")) openUdpListener(lp);
            if (!"udp".equals(protocol)) openTcpListener(lp);
        }
        pool.execute(this::scheduleLoop);
        evt("start", "项目#" + projectId + " 端口" + ports.keySet(), "");
    }

    public void stop() {
        running = false;
        for (ServerSocket socket : tcpListeners) { try { socket.close(); } catch (IOException ignored) {} }
        tcpListeners.clear();
        for (Session session : tcpSessions) {
            session.dead = true;
            try { session.game.close(); } catch (IOException ignored) {}
            if (session.active != null) session.active.closeQuietly();
            if (session.backup != null) session.backup.closeQuietly();
        }
        tcpSessions.clear();
        for (UdpProxy u : udpProxies) { try { u.closeAll(); } catch (Exception ignored) { } }   // 解除阻塞中 receive, 监督循环退出
        evt("stop", "SDK停止", ""); flushReport(); pool.shutdownNow();
    }

    /** 全SDK唯一周期线程: 5s tick。游戏未连接(休眠)时 0 网络活动; 30s批量上报事件 */
    private void scheduleLoop() {
        int tick = 0;
        while (running) {
            try { Thread.sleep(5000); } catch (InterruptedException e) { return; }
            tick++;
            boolean active = activeSessions.get() > 0 || udpActive();   // ★第卅七轮: 纯UDP项目也算活跃(旧版永不重调度/探针)
            if (active && idle) { idle = false; evt("idle_exit", "游戏连接到达, 恢复调度探测", ""); }
            if (active) {
                probeCurrent();                                   // 探活主节点
                if (tick % 3 == 0) udpKeepalive();                // UDP隧道保活/换节点重挂(15s一次)
                if (tick % 60 == 0) { try { refreshNodes(); } catch (Exception ignored) { } } // 每5分钟全量重排
            } else if (!idle) {
                idle = true; evt("idle_enter", "游戏已全部断开, 进入休眠(零网络活动)", "");
            }
            if (tick % 6 == 0) flushReport();                     // 30s一批
        }
    }

    public void refreshNodes() throws IOException {
        long now = System.currentTimeMillis();
        if (now - lastNodesTry < 3000) return;                    // 节流: 重挂风暴下每3s最多打一次调度
        lastNodesTry = now;
        try {
        JSONObject r = api("/sdk/v1/nodes?token=" + token);
        if (r.getInt("code") != 0) {
            if (now - lastSchedFailAt >= 10000) {                 // 同类失败10s只报一条, 防日志刷屏
                lastSchedFailAt = now;
                evt("sched_fail", "调度被拒: " + r.optString("msg"), "");
            }
            return;
        }
        JSONArray nodes = r.getJSONObject("data").getJSONArray("nodes");
        ranked.clear();
        for (int i = 0; i < nodes.length(); i++) ranked.add(nodes.getJSONObject(i).getString("ip"));
        } catch (JSONException e) { throw new IOException("nodes-json: " + e); }
        if (!ranked.isEmpty() && nodeIp == null) nodeIp = ranked.get(0);
        pool.execute(this::rankByRtt);           // 玩家侧实测排序(后台执行不阻塞)
    }

    /** 全部候选节点 PING/PONG 实测RTT, 升序重排队列, 首位=最优 */
    void rankByRtt() {
        long t0 = System.currentTimeMillis();
        if (t0 - lastRankAt < 30000) return;      // 第卌轮: 探针连接也吃节点握手预算, 30s 最多一轮全池测速
        if (anyPortBulk()) { return; }            // ★第卌二轮: 下载并行风暴期间全池测速静默(HELLO让路给游戏下载)
        lastRankAt = t0;
        java.util.List<String> snapshot = new java.util.ArrayList<>(ranked);
        final java.util.Map<String, Long> rtt = new java.util.HashMap<>();
        for (String ip : snapshot) { long r = measureRtt(ip); rtt.put(ip, r < 0 ? (r == -1 ? Long.MAX_VALUE - 1 : Long.MAX_VALUE) : r); }
        // 用 Collections.sort + 匿名 Comparator(API1起可用);
        // 严禁 List.sort / Comparator.comparingLong 这类 API24+ 库函数 —— minSdk21 老机必崩
        java.util.Collections.sort(snapshot, new java.util.Comparator<String>() {
            @Override public int compare(String a, String b) {
                return Long.compare(rtt.get(a), rtt.get(b));
            }
        });
        synchronized (ranked) { ranked.clear(); ranked.addAll(snapshot); }
        if (!snapshot.isEmpty()) {
            StringBuilder sb = new StringBuilder("测速排序: ");
            // ★第卌二轮: 旧版把"预算满没探"(measureRtt返回-1)也显示成"超时", 误导取证以为节点死了
            for (String ip : snapshot) sb.append(ip).append('=').append(
                rtt.get(ip) == Long.MAX_VALUE ? "超时" : rtt.get(ip) == Long.MAX_VALUE - 1 ? "未探(预算)" : rtt.get(ip) + "ms").append(" | ");
            evt("sched_ok", sb.toString(), "");
            String best = snapshot.get(0);
            if (!best.equals(nodeIp) && rtt.get(best) > 0) nodeIp = best;   // ★第卌二轮: 首位也没探成=全被预算挡, 不换主
        }
    }

    /** TCP连隧道口发PING量PONG往返; 失败=Infinity; 预算不足=-1(本轮不探, 严禁判死) */
    long measureRtt(String ip) {
        if (!helloAllow(ip)) return -1;            // 第卌轮: 节点封的是"每IP每分钟新连接总数", 探针同样吃预算
        long t0 = System.nanoTime();
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(ip, tunnelPort), 1500);
            s.setSoTimeout(1500);
            s.setTcpNoDelay(true);
            s.getOutputStream().write(frame(T_PING, new byte[0]));
            s.getOutputStream().flush();
            DataInputStream in = new DataInputStream(s.getInputStream());
            byte type = in.readByte();
            in.readInt();                        // len(PONG为0)
            if (type == T_PONG) return (System.nanoTime() - t0) / 1000000;
        } catch (Exception ignored) { }
        return Long.MAX_VALUE;
    }

    /** ★第卌二轮: 该游戏端口当前是否处于"大流量(下载并行)"态 */
    boolean portBulk(int port) { Long u = bulkUntil.get(port); return u != null && u > System.currentTimeMillis(); }
    boolean anyPortBulk() {
        long t = System.currentTimeMillis();
        for (Long u : bulkUntil.values()) if (u != null && u > t) return true;
        return false;
    }

    /**
     * 第卌轮核心闸: 对"同一节点"的所有出网连接(HELLO隧道+测速探针)按滑窗限流。
     * 服务端反DDoS=120连接/分/IP即封300s(每节点独立计数), 预算100/节点=留20余量+四闸防失控。
     * (旧版事故: 热更新40+并发×主备双隧 + 断口重挂 + 每3s全池测速 = 8节点同时把玩家IP拉黑;
     *  反转过瘾(第卌二轮): 预算砍到40又被双隧打满 → 排队超时 → 引擎掐游戏连接 = "下载异常重试"。)
     */
    synchronized boolean helloAllow(String ip) {
        if (ip == null || ip.isEmpty()) return false;
        long t = System.currentTimeMillis();
        if (helloWin.size() > 40) {                // 摘除1分钟无活动的旧窗口, 防节点池轮换后Map只涨不清
            java.util.Iterator<java.util.Map.Entry<String, java.util.ArrayDeque<Long>>> it = helloWin.entrySet().iterator();
            while (it.hasNext()) { java.util.Map.Entry<String, java.util.ArrayDeque<Long>> e = it.next();
                if (e.getValue().isEmpty() || t - e.getValue().peekLast() > 60000) it.remove(); }
        }
        java.util.ArrayDeque<Long> w = helloWin.get(ip);
        if (w == null) { w = new java.util.ArrayDeque<>(); helloWin.put(ip, w); }
        while (!w.isEmpty() && t - w.peekFirst() > 60000) w.pollFirst();
        if (w.size() >= HELLO_BUDGET_PER_NODE) return false;
        w.addLast(t);
        return true;
    }

    /** 第卌轮: 按端口钉线 —— 同一游戏端口的所有并发连接固定走同一条节点线路; 线断了才重选 */
    String nodeFor(int port) {
        String pin = portPin.get(port);
        if (pin != null && ranked.contains(pin)) return pin;
        if (pin != null) portPin.remove(port);
        String pick = (nodeIp != null && ranked.contains(nodeIp)) ? nodeIp
                : (!ranked.isEmpty() ? ranked.get(0) : nodeIp);
        if (pick != null) portPin.put(port, pick);
        return pick;
    }

    /** 探活当前节点: 失联/延迟劣化 -> 立即从队列摘除并热切(仅活跃时由tick驱动) */
    private void probeCurrent() {
        String cur = nodeIp;
        if (cur == null) return;
        if (bulkSessions.get() > 0 || anyPortBulk()) return;  // 第卌轮+第卌二轮: 热更新流量期间(RTT必然虚高)探针全静默, 单线跑完不被误切
        long rtt = measureRtt(cur);
        if (rtt < 0) return;                       // 预算不足: 本轮不探, 更不判死
        if (rtt == Long.MAX_VALUE) { evt("node_down", "主节点失联(疑被攻击/宕机), 热切", cur); dropAndSwap(cur, "失联"); }
        else if (rtt > 2000) { evt("rtt_bad", "主节点延迟劣化 " + rtt + "ms", cur); dropAndSwap(cur, "延迟" + rtt + "ms"); }
    }

    synchronized void dropAndSwap(String badIp, String reason) {
        if (badIp == null || badIp.isEmpty()) return;
        ranked.remove(badIp);
        portPin.values().remove(badIp);            // 第卌轮: 被摘除的节点同时解除端口钉线, 下条连接自动重选
        if (badIp.equals(nodeIp)) {
            String next = ranked.isEmpty() ? null : ranked.get(0);
            nodeIp = next;
            if (next != null) evt("node_switch", "热切: " + badIp + "(" + reason + ") -> " + next, next);
        }
    }

    // ================= TCP 本地代理 =================
    private void openTcpListener(final int localPort) throws IOException {
        final int targetPort = ports.get(localPort);
        final ServerSocket listener = new ServerSocket(localPort, 64, InetAddress.getByName("127.0.0.1"));
        tcpListeners.add(listener);
        pool.execute(() -> {
            try (ServerSocket ss = listener) {
                while (running) {
                    Socket game = ss.accept();
                    pool.execute(() -> handleTcp(game, targetPort));
                }
            } catch (IOException e) { /* 端口占用/stop */ }
        });
    }

    // ============================================================
    // 会话保持层(毫秒级无缝切换): 与 PC 版同设计
    //   游戏 <-> [本地socket永不重置] <-> Session <-> 主隧道 + 备隧道(双写镜像)
    //   主通道断口 -> 备通道升主(数据完整零丢包) -> 异步再补一条备通道
    //   无备通道可用时: 断口字节进 pending(gapMax 默认64KB) 重挂新节点后重放
    // ============================================================
    private void handleTcp(Socket game, int targetPort) {
        Session session = new Session(game, targetPort);
        tcpSessions.add(session);
        if (!running) { try { game.close(); } catch (IOException ignored) {} return; }
        session.start();
    }

    final class Tunnel {
        final Socket sock; final DataInputStream in; final java.io.OutputStream out;
        final String nodeIp; volatile boolean live = true;
        volatile long lastBeat = System.currentTimeMillis();   // 在隧心跳: 任何下行帧刷新(第卅三轮)
        Tunnel(Socket s, String ip) throws IOException { sock = s; in = new DataInputStream(s.getInputStream()); out = s.getOutputStream(); nodeIp = ip; }
        void closeQuietly() { try { sock.close(); } catch (IOException ignored) { } }
    }

    final class Session {
        final Socket game; final int targetPort;
        final String sid;                                       // 网关会话锚: 本局连接不变, 主/备/重挂复用
        volatile Tunnel active, backup;
        final java.util.ArrayDeque<byte[]> pending = new java.util.ArrayDeque<>();
        int pendLen; volatile boolean dead, switching;
        volatile long downBytes; volatile boolean bulk;         // 第卌轮: 大流量(热更新)检测 → 单线专用通道
        volatile long upAct = System.currentTimeMillis();       // ★第卌二轮: 最近一次上行帧时间(idleEnd 判据用)
        private static final long BULK_BYTES = 2 * 1024 * 1024;

        Session(Socket g, int tp) {
            game = g; targetPort = tp;
            byte[] sb = new byte[10]; new SecureRandom().nextBytes(sb); sid = hexStr(sb);
        }

        void start() {
            // ★第卌二轮: 端口级并发计数 —— 同端口并发≥6路 = 游戏热更新并行下载特征(业务长连口恒1-2路)。
            //   这类会话: 不配镜像备隧(HELLO量直接减半)、全局探针静默; bulk 态每有新连接就续期120s。
            //   (map 上 synchronized 做复合计数——严禁 Map.merge 等 API24+ 函数, minSdk21 老机必崩)
            int c;
            synchronized (portConc) {
                Integer prev = portConc.get(targetPort);
                c = (prev == null ? 0 : prev) + 1;
                portConc.put(targetPort, c);
            }
            // ★第52轮: 豁免判据用【既有】bulk态(此前连接已达≥6路标过), 不读本轮刚自增的计数 ——
            //   热更口在 c=6 时就被下方标记为 bulk, 到 65 路时 bulkNow=true → 改用256线, 版本/下载连接放行;
            //   而"从未来过、一上来就冲到65"的业务口 bulkNow=false → 仍被64线熔断(保留卅三轮风暴兜底)。
            final boolean bulkNow = portBulk(targetPort);
            // ★第卌三轮: 熔断闸 —— 业务口超64路=重连风暴(实测今朝复古 3次/秒), 归还计数并拒掉这条新连接。
            // ★第52轮: 热更口(bulk态)改256路封顶(与服务器 ip_conn_limit 对齐), 不再掐死合法下载/版本连接。
            if (c > (bulkNow ? BULK_MAX_CONC : PORT_MAX_CONC)) {
                synchronized (portConc) {
                    Integer prev = portConc.get(targetPort);
                    int b = (prev == null ? 0 : prev) - 1;
                    if (b <= 0) portConc.remove(targetPort); else portConc.put(targetPort, b);
                }
                long now = System.currentTimeMillis();
                if (now - lastStormAt > 15000) {
                    lastStormAt = now;
                    if (bulkNow)
                        evt("conn_storm", "端口" + targetPort + "热更口并发" + c + "路超256线=下载失控(疑源站受理慢在积压), 暂拒新连接", nodeIp);
                    else
                        evt("conn_storm", "端口" + targetPort + "并发会话已达" + c + "路=重连风暴(正常游戏<50路), 新连接被熔断 —— 游戏多半进不去服在狂重连, 请查源站该端口是否受理", nodeIp);
                }
                try { game.close(); } catch (IOException ignored) { }
                return;
            }
            // ★第卌二轮: 标记放熔断之后(顺序敏感!) —— 若先标记再熔断, 任何爬到64的口都会先自标bulk而废掉64线。
            if (c >= BULK_PORT_CONC) {
                long t = System.currentTimeMillis();
                Long old = bulkUntil.put(targetPort, t + BULK_PORT_MS);
                if (old == null || old <= t)
                    evt("bulk_line", "端口" + targetPort + "并发" + c + "路=热更新大流量特征: 该口连接全部单线无镜像, 探针静默", "");
            }
            if (bulkNow) { bulk = true; bulkSessions.incrementAndGet(); }
            pool.execute(this::primaryLoop); pool.execute(this::watchdogLoop);
        }

        private void primaryLoop() {
            activeSessions.incrementAndGet();
            try {
                game.setTcpNoDelay(true);
                try {
                    Tunnel t = openTunnel(nodeFor(targetPort), false);   // 第卌轮: 同端口并发连接钉在同一条线上
                    active = t;
                    tunnelReader(t);
                } catch (Exception e) {
                    // ★第卅七轮: 首条连接不再"一次即死"——进与断口完全相同的重挂路径(窗口默认60s),
                    //   游戏 socket 全程保持; 上行字节期间进 pending 缓冲, 重挂后按序重放。
                    String bad0 = nodeIp;
                    evt("tunnel_err", "初始建盾失败: " + e.getMessage() + " (自动重挂中, 游戏连接保持)", bad0);
                    // ★第卌二轮: 排队超时≠节点故障, 不摘节点不拆线(交重挂循环继续等预算)
                    if (String.valueOf(e.getMessage()).indexOf("排队超时") < 0) dropAndSwap(bad0, "初始建盾失败");
                    onDrop(bad0);
                }
                pool.execute(this::ensureBackup);
                // 本线程: 游戏上行
                java.io.InputStream gis = game.getInputStream();
                byte[] buf = new byte[16384]; int n;
                while (!dead && (n = gis.read(buf)) > 0) {
                    upAct = System.currentTimeMillis();                  // ★第卌二轮: 记录游戏还在发请求
                    sendFrame(frame(T_DATA, gcmEncrypt(buf, n)));
                }
            } catch (Exception e) {
                /* 游戏socket读异常/关闭 */
            } finally {
                dead = true;
                if (active != null) active.closeQuietly();
                if (backup != null) backup.closeQuietly();
                try { game.close(); } catch (IOException ignored) { }
                activeSessions.decrementAndGet(); tcpSessions.remove(this);
                if (bulk) bulkSessions.decrementAndGet();     // 第卌轮: 会话终了必还大流量计数(探针静默门随之复位)
                // ★第卌二轮: 端口并发计数归还(bulkUntil 靠时间自然过期, 不清)
                synchronized (portConc) {
                    Integer prev = portConc.get(targetPort);
                    int c2 = (prev == null ? 0 : prev) - 1;
                    if (c2 <= 0) portConc.remove(targetPort); else portConc.put(targetPort, c2);
                }
            }
        }

        /**
         * 开一条到节点的隧道(HELLO握手)。
         * @param soft true=备镜像/探针等"让路"通道: 预算紧张时最多排队6s即放弃(稍后 watchdog 自动补位);
         *             false=游戏主隧: 排队50s尽力保住游戏连接 —— 旧版20s超时→resume窗口被整段吃掉→
         *             引擎主动 game.close() 掐死下载 = "下载异常重试"的直接来源(第卌二轮铁证 resume_fail×47)。
         */
        Tunnel openTunnel(String ip, boolean soft) throws IOException {
            if (ip == null) throw new IOException("暂无可调度节点(排队等待调度)");
            // 第卌轮: 握手预算闸 —— 所有新开隧必须先领预算, 领不到就排队, 物理杜绝自DDoS。
            long w0 = System.currentTimeMillis();
            final long maxWait = soft ? 6000 : 50000;
            while (!helloAllow(ip)) {
                if (dead || System.currentTimeMillis() - w0 > maxWait) throw new IOException("握手预算排队超时(节点保护中)");
                try { Thread.sleep(soft ? 600 : 400); } catch (InterruptedException e) { throw new IOException("interrupted"); }
            }
            Socket s = new Socket();
            SocketGuard g = GUARD;                    // ★第卅九轮回2: VPN 在跑时节点 socket 不走隧道(防自环)
            if (g != null) { try { g.protect(s); } catch (Throwable ignored) { } }
            s.connect(new InetSocketAddress(ip, tunnelPort), 3000);
            s.setTcpNoDelay(true);
            Tunnel t = new Tunnel(s, ip);
            byte[] hello = buildHello(targetPort, sid);
            t.out.write(hello); t.out.flush();
            Frame pong = readFrame(t.in);          // 等 PONG(握手完成)
            if (pong == null || pong.type != T_PONG) {
                s.close();
                evt("hello_reject", "节点收到HELLO后拒绝(断开/非PONG): aes_key/项目/端口配置不匹配", ip);
                throw new IOException("bad pong");
            }
            return t;
        }

        synchronized void sendFrame(byte[] f) {
            boolean a = false, b = false; String dropIp = null;
            Tunnel act = active;
            if (act != null && act.live) {
                try { act.out.write(f); act.out.flush(); a = true; }
                catch (Exception e) { active = null; act.live = false; act.closeQuietly(); dropIp = act.nodeIp; }
            }
            Tunnel bak = backup;
            if (bak != null && bak.live) {
                try { bak.out.write(f); bak.out.flush(); b = true; }
                catch (Exception e) { backup = null; bak.live = false; bak.closeQuietly(); }
            }
            if (!a && !b) {
                pending.add(f); pendLen += f.length;
                while (pendLen > gapMax && pending.size() > 1) pendLen -= pending.poll().length;
            }
            // ★第卅七轮: 主隧道同步写异常时阻塞读线程可能永不出局(半开), 旧版只置null会冻结成
            //   "无主无备无重挂"。立即销毁 socket 并走既有升主/重挂(备道毫秒级接管)。
            if (dropIp != null) onDrop(dropIp);
        }

        void tunnelReader(final Tunnel t) {
            pool.execute(() -> {
                try {
                    while (!dead) {
                        Frame fr = readFrame(t.in);
                        if (fr == null) break;
                        t.lastBeat = System.currentTimeMillis();      // 任何下行帧(PONG/DATA)=隧道活着
                        if (t == active && fr.type == T_DATA) {        // 备通道下行静默丢弃(镜像语义)
                            if (!bulk) {                               // 第卌轮: 下行灌满2MB = 热更新大流量
                                downBytes += fr.payload.length;
                                if (downBytes >= BULK_BYTES) enterBulk();
                            }
                            game.getOutputStream().write(gcmDecrypt(fr.payload));
                            game.getOutputStream().flush();
                        }
                    }
                } catch (Exception ignored) { }
                t.live = false;
                if (t == active) {
                    active = null;
                    // ★第卌二轮: 静默期(双向>15s无流量)EOF = 上游/源站正常收尾(HTTP keep-alive到期/会话结束),
                    //   不是节点故障! 旧版在此 dropAndSwap(把健康节点踢出队列+热切)+重挂(白吃握手预算)
                    //   = node_down×57/node_switch×22 风暴来源。正确姿势=回收本会话, 游戏自会发新连接。
                    long quiet = System.currentTimeMillis() - Math.max(t.lastBeat, upAct);
                    if (pendLen == 0 && quiet > IDLE_END_MS) {
                        if (!dead) evt("tunnel_eof", "上游空闲收尾正常断链(非节点故障), 会话回收", t.nodeIp);
                        dead = true;
                        try { game.close(); } catch (IOException ignored2) { }
                        return;
                    }
                    onDrop(t.nodeIp);
                }
                else if (t == backup) backup = null;
            });
        }

        /** 第卌轮: 热更新专用单线通道 —— 大流量会话卸掉镜像备份(隧道数立省一半),
         *  后续断口重挂也只回钉住的那条线; 期间全局探针静默, 不把"下载排队RTT"误判成节点劣化。 */
        void enterBulk() {
            bulk = true;
            bulkSessions.incrementAndGet();
            Tunnel b = backup;
            if (b != null) { backup = null; b.live = false; b.closeQuietly(); }
            evt("bulk_line", "检测到本连接下行超2MB: 已切热更新单线专用通道(备镜像已卸, 断口自动重发)",
                active != null ? active.nodeIp : null);
        }

        synchronized void flushPending(Tunnel t) {
            while (!pending.isEmpty()) {
                try { t.out.write(pending.poll()); t.out.flush(); }
                catch (Exception e) { return; }
            }
            pendLen = 0;
        }

        void onDrop(String badIp) {
            if (dead || switching) return;
            switching = true;
            // 路径1: 备通道升主 —— 毫秒级零丢包
            if (backup != null && backup.live) {
                active = backup; backup = null;
                dropAndSwap(badIp, "主通道故障");
                nodeIp = active.nodeIp;                                   // 以升主通道为准(dropAndSwap可能先指到别家)
                portPin.put(targetPort, active.nodeIp);                   // 第卌轮: 升主后该端口继续沿这条线走
                if (ranked != null) { ranked.remove(active.nodeIp); ranked.add(0, active.nodeIp); }
                flushPending(active);
                switching = false;
                evt("backup_promote", "备通道升主, 原节点" + badIp + "故障, 游戏零丢包毫秒级切换", active.nodeIp);
                pool.execute(this::ensureBackup);
                return;
            }
            // 路径2: 无备通道 -> 断口缓冲 + 重挂(宽限期默认30s, 指数退避, 连续失败周期重调度)
            dropAndSwap(badIp, "盾节点断口");
            evt("node_down", "主隧道断开(无备通道), 游戏连接保持, 重挂中(缓冲" + pendLen + "B, 窗口" + (resumeGraceMs / 1000) + "s)", badIp);
            pool.execute(() -> {
                long deadline = System.currentTimeMillis() + resumeGraceMs;
                final int[] BACK = {300, 500, 800, 1200, 2000, 3000};
                int tries = 0;
                while (!dead && System.currentTimeMillis() < deadline) {
                    if (ranked.isEmpty()) { try { refreshNodes(); } catch (IOException ignored) { } }
                    String ip = nodeFor(targetPort);                      // 第卌轮: 重挂优先回到本端口钉住的线(热更新单线跑完)
                    if (ip == null) { try { Thread.sleep(300); } catch (InterruptedException e) { return; } continue; }
                    try {
                        Tunnel t = openTunnel(ip, false);
                        active = t; nodeIp = ip;
                        tunnelReader(t);
                        flushPending(t);
                        switching = false;
                        evt("resume_ok", "已重挂 " + ip + ", 游戏无掉线(第" + (tries + 1) + "次尝试)", ip);
                        pool.execute(this::ensureBackup);
                        return;
                    } catch (Exception e) {
                        // ★第卌二轮: "预算排队超时"不是节点故障 —— 不摘线不换节点, 下一轮继续回钉住的线等预算
                        if (String.valueOf(e.getMessage()).indexOf("排队超时") < 0) dropAndSwap(ip, "重挂失败");
                        tries++;
                        if (tries % 4 == 0) { try { refreshNodes(); } catch (IOException ignored) { } }  // 换一换全池视野
                        try { Thread.sleep(BACK[Math.min(tries - 1, BACK.length - 1)]); } catch (InterruptedException ie) { return; }
                    }
                }
                evt("resume_fail", (resumeGraceMs / 1000) + "秒内无法重挂任何节点(全部失联/握手被拒), 游戏断开", badIp);
                dead = true;
                try { game.close(); } catch (IOException ignored) { }
            });
        }

        // ---- 在隧心跳看门狗(第卅三轮): 哑死盲区补位 ----
        //   节点被DDoS打宕机/断网时 TCP 半开不报错, 阻塞读线程永不出局 -> close/error 判死失效,
        //   游戏冻在"主道无响应+备道下行被镜像丢弃"上。本线程每2s对主/备发 PING 并检查 lastBeat:
        //   主道6s无下行 = 主动 close -> 读线程抛IOException走既有 onDrop(备道毫秒级升主);
        //   备道12s无下行 = 静默重建镜像备份。与 PC/iOS 同参数。
        void watchdogLoop() {
            byte[] ping = frame(T_PING, new byte[0]);
            while (!dead) {
                try { Thread.sleep(2000); } catch (InterruptedException e) { return; }
                if (dead) return;
                Tunnel a = active;
                if (a != null && a.live) {
                    if (System.currentTimeMillis() - a.lastBeat > 6000) {
                        evt("hb_dead", "心跳判主隧道6秒无响应(疑节点宕机/断网哑死), 主动无缝切换", a.nodeIp);
                        a.live = false; a.closeQuietly();   // 读线程出局自动触发 onDrop
                    } else { try { a.out.write(ping); a.out.flush(); } catch (Exception ignored) { } }
                }
                Tunnel b = backup;
                if (b != null && b.live) {
                    if (System.currentTimeMillis() - b.lastBeat > 12000) {
                        evt("hb_backup", "备通道心跳超时, 重建镜像备份", b.nodeIp);
                        b.live = false; b.closeQuietly();
                        pool.execute(this::ensureBackup);
                    } else { try { b.out.write(ping); b.out.flush(); } catch (Exception ignored) { } }
                } else if (a != null && a.live && !switching && !bulk) pool.execute(this::ensureBackup);  // 备道缺失: 持续补位(大流量单线除外)
            }
        }

        void ensureBackup() {
            if (dead || bulk || backup != null || ranked == null) return;   // 第卌轮: bulk=热更新单线通道, 永久无备镜像
            if (portBulk(targetPort)) return;   // ★第卌二轮: 下载并行的短连接一律无镜像(HELLO量减半, 预算留给主隧)
            String cand = null;
            synchronized (ranked) {
                for (String ip : ranked) if (!ip.equals(nodeIp)) { cand = ip; break; }
            }
            if (cand == null) return;
            try {
                Tunnel t = openTunnel(cand, true);      // ★第卌二轮: 备隧=让路通道(soft), 预算紧张6s内拿不到即弃, watchdog 稍后补位
                backup = t;
                tunnelReader(t);
                evt("backup_up", "备通道待命(双写镜像)", cand);
            } catch (Exception ignored) { }
        }
    }

    // ================= UDP 本地代理(第卅七轮: 监督自愈) =================
    // 旧版单监听三绝症: ①节点断口后 send 抛异常线程退出, 监听永不重建(UDP永久黑洞)
    // ②节点侧UDP会话60s空闲回收, 静默期映射消失后续.datagram被当孤儿丢(SDK从不重发HELLO)
    // ③调度热切后UDP仍打旧节点。现改为"游戏口常驻 + 隧道socket可重建": 断口即重建并补发
    //   HELLO(sid 全程不变=网关认人不认门), 活跃期15s一帧PING续命, 45s重握手防节点侧过期。
    private final java.util.List<UdpProxy> udpProxies = java.util.Collections.synchronizedList(new java.util.ArrayList<UdpProxy>());

    private void openUdpListener(final int localPort) {
        final int targetPort = ports.get(localPort);
        UdpProxy up = new UdpProxy(localPort, targetPort);
        udpProxies.add(up);
        pool.execute(up::run);
    }

    boolean udpActive() {
        long now = System.currentTimeMillis();
        for (UdpProxy u : udpProxies) if (u.node != null && now - u.lastAct < 60000) return true;
        return false;
    }
    void udpKeepalive() { for (UdpProxy u : udpProxies) { try { u.keepalive(); } catch (Exception ignored) { } } }
    String pickIp() {
        if (nodeIp != null) return nodeIp;
        String r = null;
        if (!ranked.isEmpty()) { try { r = ranked.get(0); } catch (Exception ignored) { } }
        return r;
    }

    final class UdpProxy {
        final int localPort, targetPort; final String sid;
        volatile DatagramSocket game, node; volatile String curIp;
        volatile long helloT, lastAct = System.currentTimeMillis(), lastPing;
        UdpProxy(int lp, int tp) {
            localPort = lp; targetPort = tp;
            byte[] sb = new byte[10]; new SecureRandom().nextBytes(sb);
            sid = hexStr(sb);                       // UDP会话号: 本监听生命周期不变(换隧道/换节点都复用)
        }
        public void run() {
            try { game = new DatagramSocket(localPort, InetAddress.getByName("127.0.0.1")); }
            catch (Exception e) { evt("tunnel_err", "UDP本地端口" + localPort + "绑定失败: " + e.getMessage(), ""); return; }
            Thread down = new Thread(this::downLoop); down.setDaemon(true); down.start();
            byte[] buf = new byte[65536];
            while (running) {
                DatagramPacket gp = new DatagramPacket(buf, buf.length);
                try { game.receive(gp); } catch (Exception e) { break; }          // 游戏口关闭/stop
                lastAct = System.currentTimeMillis();
                DatagramSocket nd = ensureTunnel();
                if (nd == null) continue;
                try {
                    if (lastAct - helloT > 45000) sendHello(nd);                  // 节点侧空闲阈值60s: 45s即重握手
                    byte[] f = frame(T_DATA, gcmEncrypt(gp.getData(), gp.getLength()));
                    nd.send(new DatagramPacket(f, f.length));
                } catch (Exception e) {
                    DatagramSocket old = node; node = null;
                    if (old != null) { try { old.close(); } catch (Exception ignored) { } }   // ICMP不可达/网络错: 下一包重建
                }
            }
            closeAll();
        }
        DatagramSocket ensureTunnel() {
            DatagramSocket nd = node;
            String best = pickIp();
            if (best == null) { try { refreshNodes(); } catch (IOException ignored) { } best = pickIp(); if (best == null) return null; }
            if (nd != null && best.equals(curIp)) return nd;
            if (nd != null) { try { nd.close(); } catch (Exception ignored) { } }  // 换节点/断口重建: 关旧口, 读线程随之出局
            try {
                DatagramSocket s = new DatagramSocket();
                s.connect(InetAddress.getByName(best), tunnelPort);
                node = s; curIp = best;
                sendHello(s);
                return s;
            } catch (Exception e) { node = null; return null; }
        }
        void sendHello(DatagramSocket s) {
            try { byte[] h = buildHello(targetPort, sid); s.send(new DatagramPacket(h, h.length)); helloT = System.currentTimeMillis(); }
            catch (Exception ignored) { }
        }
        void downLoop() {
            byte[] buf = new byte[65536];
            while (running) {
                DatagramSocket nd = node;
                if (nd == null) { try { Thread.sleep(300); } catch (InterruptedException e) { return; } continue; }
                DatagramPacket np = new DatagramPacket(buf, buf.length);
                try { nd.receive(np); } catch (Exception e) { if (node == nd) node = null; continue; }   // 关闭/ICMP: 置坏, 发包侧重建
                if (node != nd) continue;                                          // 陈旧隧道的回包: 丢弃
                lastAct = System.currentTimeMillis();
                if (np.getLength() < 6 || buf[0] != T_DATA) continue;              // PONG等控制帧: 只用于续命
                try {
                    byte[] payload = new byte[np.getLength() - 5];
                    System.arraycopy(buf, 5, payload, 0, payload.length);
                    byte[] plain = gcmDecrypt(payload);
                    DatagramSocket g = game;
                    if (g != null && !g.isClosed()) g.send(new DatagramPacket(plain, plain.length, InetAddress.getByName("127.0.0.1"), localPort));
                } catch (Exception ignored) { }
            }
        }
        void keepalive() {                                                         // scheduleLoop 每15s驱动
            DatagramSocket nd = node;
            if (nd == null) return;
            long now = System.currentTimeMillis();
            if (now - lastAct > 60000) return;                                     // 玩家侧全静默: 零流量(省电原则)
            String best = pickIp();
            if (best != null && !best.equals(curIp)) {                             // 调度换节点: UDP即时重挂(游戏口不动)
                evt("udp_rebind", "调度节点变更, UDP隧道重挂新节点", best);
                if (node != null) { try { node.close(); } catch (Exception ignored) { } }
                node = null; ensureTunnel(); return;
            }
            if (now - helloT > 45000) sendHello(nd);
            else if (now - lastPing > 15000) {
                lastPing = now;
                try { byte[] f = frame(T_PING, new byte[0]); nd.send(new DatagramPacket(f, f.length)); } catch (Exception ignored) { }
            }
        }
        void closeAll() {
            DatagramSocket n = node; node = null; if (n != null) { try { n.close(); } catch (Exception ignored) { } }
            DatagramSocket g = game; game = null; if (g != null) { try { g.close(); } catch (Exception ignored) { } }
        }
    }

    // ================= 帧与密码学(实例方法, 无共享缓冲, 线程安全) =================
    static class Frame { int type; byte[] payload; Frame(int t, byte[] p) { type = t; payload = p; } }

    static byte[] frame(byte type, byte[] payload) {
        ByteBuffer b = ByteBuffer.allocate(5 + payload.length);
        b.put(type).putInt(payload.length).put(payload);
        return b.array();
    }

    static Frame readFrame(InputStream in) throws IOException {
        int type = in.read();
        if (type < 0) return null;
        int len = (in.read() << 24) | (in.read() << 16) | (in.read() << 8) | in.read();
        // 第卅九轮回4 铁证修复: PONG 等控制帧 payload 为空(整帧仅5字节) —— 旧判定 len<=0 把
        // 服务端每一次握手成功都读成坏帧, 真机全池 hello_reject(网关机日志里其实已回PONG)。0 必须合法。
        if (len < 0 || len > 655360) return null;
        byte[] payload = new byte[len];
        int off = 0;
        while (off < len) { int r = in.read(payload, off, len - off); if (r < 0) return null; off += r; }
        return new Frame(type, payload);
    }

    byte[] buildHello(int port, String sid) {
        byte[] nb = new byte[8]; new SecureRandom().nextBytes(nb);
        String nonce = hexStr(nb);
        String auth = hmac(aesKey, projectId + ":" + port + ":" + nonce);
        String json = "{\"v\":1,\"project_id\":" + projectId + ",\"port\":" + port
                + ",\"nonce\":\"" + nonce + "\",\"auth\":\"" + auth + "\",\"proto\":\"tcp\""
                + ",\"sid\":\"" + sid + "\"}";
        return frame(T_HELLO, json.getBytes());
    }

    byte[] gcmEncrypt(byte[] data, int len) throws Exception {
        byte[] iv = new byte[12]; new SecureRandom().nextBytes(iv);
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(aesKey, "AES"), new GCMParameterSpec(128, iv));
        byte[] ct = c.doFinal(data, 0, len);          // 尾部含16B tag
        byte[] out = new byte[12 + ct.length];
        System.arraycopy(iv, 0, out, 0, 12);
        System.arraycopy(ct, 0, out, 12, ct.length);
        return out;
    }

    byte[] gcmDecrypt(byte[] frame) throws Exception {
        if (frame == null || frame.length < 29) throw new SecurityException("bad frame");
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(aesKey, "AES"),
                new GCMParameterSpec(128, frame, 0, 12));
        return c.doFinal(frame, 12, frame.length - 12);
    }

    Cipher newCipher(int mode, byte[] iv) throws Exception {
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
        c.init(mode, new SecretKeySpec(aesKey, "AES"), new GCMParameterSpec(128, iv));
        return c;
    }
    static byte[] randomIv() { byte[] iv = new byte[12]; new SecureRandom().nextBytes(iv); return iv; }

    static String hmac(byte[] key, String msg) {
        try {
            Mac m = Mac.getInstance("HmacSHA256");
            m.init(new SecretKeySpec(key, "HmacSHA256"));
            return hexStr(m.doFinal(msg.getBytes("UTF-8")));
        } catch (Exception e) { throw new RuntimeException(e); }
    }

    // ================= HTTP =================
    JSONObject api(String path) throws IOException {
        URL u = new URL(cpBase + path);
        HttpURLConnection c = (HttpURLConnection) u.openConnection();
        c.setConnectTimeout(8000); c.setReadTimeout(8000);
        try (InputStream in = c.getInputStream()) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] b = new byte[4096]; int n;
            while ((n = in.read(b)) > 0) bo.write(b, 0, n);
            return new JSONObject(bo.toString("UTF-8"));
        } catch (JSONException e) { throw new IOException("api-json: " + e); }
    }

    /** JSON POST(事件批量上报用) */
    JSONObject apiPost(String path, JSONObject body) throws IOException {
        URL u = new URL(cpBase + path);
        HttpURLConnection c = (HttpURLConnection) u.openConnection();
        c.setConnectTimeout(8000); c.setReadTimeout(8000);
        c.setRequestMethod("POST");
        c.setRequestProperty("Content-Type", "application/json");
        c.setDoOutput(true);
        byte[] data = body.toString().getBytes("UTF-8");
        try (OutputStream os = c.getOutputStream()) { os.write(data); os.flush(); }
        try (InputStream in = c.getInputStream()) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] b = new byte[4096]; int n;
            while ((n = in.read(b)) > 0) bo.write(b, 0, n);
            return new JSONObject(bo.toString("UTF-8"));
        } catch (JSONException e) { throw new IOException("api-json: " + e); }
    }

    // ================= hex =================
    static byte[] hex(String s) {
        byte[] o = new byte[s.length() / 2];
        for (int i = 0; i < o.length; i++) o[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        return o;
    }
    static String hexStr(byte[] b) {
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x));
        return s.toString();
    }
}
