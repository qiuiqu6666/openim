<template>
  <el-space direction="vertical" fill style="width: 100%">
    <el-card>
      <el-form inline @submit.prevent="load(1)">
        <el-form-item label="用户">
          <el-input v-model="query.userID" placeholder="公开ID，例如 @ivarf8yuh2" />
        </el-form-item>
        <el-form-item label="类型">
          <el-select v-model="query.type" clearable placeholder="全部" style="width: 120px">
            <el-option label="建议" value="suggestion" />
            <el-option label="错误" value="bug" />
            <el-option label="其他" value="other" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="query.status" clearable placeholder="全部" style="width: 140px">
            <el-option label="已收到" value="received" />
            <el-option label="处理中" value="processing" />
            <el-option label="已解决" value="resolved" />
          </el-select>
        </el-form-item>
        <el-form-item label="时间">
          <el-date-picker
            v-model="query.range"
            type="datetimerange"
            start-placeholder="开始"
            end-placeholder="结束"
            range-separator="至"
            value-format="x"
          />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" native-type="submit">查询</el-button>
        </el-form-item>
      </el-form>
      <admin-table :data="rows" v-loading="loading" empty-text="没有反馈" @row-click="open">
        <el-table-column prop="feedbackID" label="反馈 ID" min-width="220" />
        <el-table-column label="用户" min-width="200"><template #default="{ row }"><div class="feedback-identity"><strong>{{ row.userNickname || '昵称暂不可用' }}</strong><small>{{ publicID(row.userID) }}</small></div></template></el-table-column>
        <el-table-column label="反馈正文" min-width="320"><template #default="{ row }"><div class="feedback-content">{{ row.content || '—' }}</div></template></el-table-column>
        <el-table-column label="类型" width="100">
          <template #default="{ row }">{{ typeText(row.type) }}</template>
        </el-table-column>
        <el-table-column label="状态" width="120">
          <template #default="{ row }">{{ statusText(row.status) }}</template>
        </el-table-column>
        <el-table-column label="日志" width="140">
          <template #default="{ row }">{{ logText(row.sdkLogStatus) }}</template>
        </el-table-column>
        <el-table-column label="时间" min-width="180">
          <template #default="{ row }">{{ formatTime(row.createdAt) }}</template>
        </el-table-column>
      </admin-table>
      <el-pagination
        style="margin-top: 12px"
        layout="prev, pager, next"
        :page-size="20"
        :total="total"
        :current-page="pageNo"
        @current-change="load"
      />
    </el-card>
    <el-dialog v-model="visible" title="反馈详情" width="720px">
      <div v-loading="detailLoading">
        <el-descriptions :column="2" border v-if="detail.feedbackID">
          <el-descriptions-item label="用户"><div class="feedback-identity"><strong>{{ detail.userNickname || '昵称暂不可用' }}</strong><small>{{ publicID(detail.userID) }}</small></div></el-descriptions-item>
          <el-descriptions-item label="类型">{{ typeText(detail.type) }}</el-descriptions-item>
          <el-descriptions-item label="设备">{{ detail.platform }} {{ detail.deviceName }}</el-descriptions-item>
          <el-descriptions-item label="版本">{{ detail.appVersion }}</el-descriptions-item>
          <el-descriptions-item label="日志状态">{{ logText(detail.sdkLogStatus) }}</el-descriptions-item>
          <el-descriptions-item label="设备 ID">{{ detail.deviceID }}</el-descriptions-item>
          <el-descriptions-item label="提交时间">{{ formatTime(detail.createdAt) }}</el-descriptions-item>
          <el-descriptions-item label="更新时间">{{ formatTime(detail.updatedAt) }}</el-descriptions-item>
          <el-descriptions-item label="正文" :span="2">{{ detail.content }}</el-descriptions-item>
        </el-descriptions>
        <el-space wrap style="margin-top: 12px">
          <el-image v-for="shot in detail.screenshots || []" :key="shot.url" :src="shot.url" style="width: 120px; height: 120px" fit="cover" preview-teleported :preview-src-list="[shot.url]" />
        </el-space>
        <el-divider />
        <el-form label-width="80px">
          <el-form-item label="状态">
            <el-select v-model="edit.status">
              <el-option label="已收到" value="received" />
              <el-option label="处理中" value="processing" />
              <el-option label="已解决" value="resolved" />
            </el-select>
          </el-form-item>
          <el-form-item label="备注">
            <el-input v-model="edit.note" type="textarea" />
          </el-form-item>
          <el-form-item>
            <el-button type="primary" :loading="saving" @click="save">保存</el-button>
          </el-form-item>
        </el-form>
        <admin-table :data="detail.logs || []" empty-text="没有关联日志">
          <el-table-column label="日志记录">
            <template #default="{ row, $index }">
              {{ row.logRecordID }}<span v-if="$index === (detail.logs || []).length - 1">（最新）</span>
            </template>
          </el-table-column>
          <el-table-column label="上传时间">
            <template #default="{ row }">{{ formatTime(row.uploadedAt) }}</template>
          </el-table-column>
          <el-table-column label="下载" width="120">
            <template #default="{ row }">
              <el-button link type="primary" :loading="downloading.has(row.logRecordID)" @click="download(row.logRecordID)">下载</el-button>
            </template>
          </el-table-column>
        </admin-table>
      </div>
    </el-dialog>
  </el-space>
</template>

<script setup>
import { reactive, ref } from "vue";
import { ElMessage } from "element-plus";
import { api, page } from "../api/http";
import { downloadLogArchive } from "../utils/downloadLogArchive";

const loading = ref(false);
const detailLoading = ref(false);
const saving = ref(false);
const downloading = reactive(new Set());
const visible = ref(false);
const rows = ref([]);
const total = ref(0);
const pageNo = ref(1);
const detail = ref({});
const query = reactive({ userID: "", type: "", status: "", range: [] });
const types = { suggestion: "建议", bug: "错误", other: "其他" };
const statuses = { received: "已收到", processing: "处理中", resolved: "已解决" };
const logs = { not_requested: "未请求", pending: "等待关联", uploaded: "已上传", failed: "关联失败" };

function typeText(value) {
  return types[value] || value || "";
}

function statusText(value) {
  return statuses[value] || value || "";
}

function logText(value) {
  return logs[value] || value || "";
}
const edit = reactive({ status: "received", note: "" });

function formatTime(ms) {
  if (!ms) return "";
  return new Date(ms).toLocaleString();
}

async function load(n = pageNo.value) {
  pageNo.value = n;
  loading.value = true;
  try {
    const range = query.range || [];
    const data = await api("/feedback/search", {
      userID: query.userID,
      type: query.type,
      status: query.status,
      startTime: range[0] ? Number(range[0]) : 0,
      endTime: range[1] ? Number(range[1]) : 0,
      pagination: page(n, 20),
    });
    rows.value = data.feedbacks || [];
    total.value = data.total || 0;
  } catch (e) {
    ElMessage.error(e.message || "加载失败");
  } finally {
    loading.value = false;
  }
}

async function open(row) {
  visible.value = true;
  detailLoading.value = true;
  try {
    detail.value = await api("/feedback/detail", { feedbackID: row.feedbackID });
    edit.status = detail.value.status || "received";
    edit.note = detail.value.note || "";
  } catch (e) {
    ElMessage.error(e.message || "加载详情失败");
  } finally {
    detailLoading.value = false;
  }
}

async function save() {
  saving.value = true;
  try {
    const data = await api("/feedback/update", { feedbackID: detail.value.feedbackID, status: edit.status, note: edit.note });
    detail.value.status = data.status;
    detail.value.note = data.note;
    ElMessage.success("已保存");
    load();
  } catch (e) {
    ElMessage.error(e.message || "保存失败");
  } finally {
    saving.value = false;
  }
}

async function download(logRecordID) {
  if (downloading.has(logRecordID)) return;
  downloading.add(logRecordID);
  try {
    const data = await api("/feedback/log_url", { feedbackID: detail.value.feedbackID, logRecordID });
    if (!data.url) throw new Error("日志下载地址不可用");
    await downloadLogArchive(data.url, logRecordID);
  } catch (e) {
    ElMessage.error(e.message || "日志暂时不能下载");
  } finally {
    downloading.delete(logRecordID);
  }
}

load(1);
</script>

<style scoped>
.feedback-content {white-space:pre-wrap;overflow-wrap:anywhere;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:3;overflow:hidden;line-height:1.6;}
.feedback-identity {display:flex;flex-direction:column;gap:4px;overflow-wrap:anywhere;line-height:1.5;}
.feedback-identity strong {font-weight:500;color:var(--el-text-color-primary);}
.feedback-identity small {font-size:12px;color:var(--el-text-color-secondary);}
</style>
