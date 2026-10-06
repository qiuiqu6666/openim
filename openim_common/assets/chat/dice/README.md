# 聊天骰子 WebP 资源

来源：用户于 2026-10-06 提供的六个 WebP 附件。按用户要求替换原骰子 Lottie，原有 `dice_1.json` 至 `dice_6.json` 已从本资源目录删除。用户下载目录中的原始附件保持原样。

这里直接复制原始 WebP，未重绘、改色或重新编码。文件数字对应动画落定后骰子**上表面**的点数；附件顺序与结果并非完全相同，第 5 个附件落定为 6 点，第 6 个附件落定为 5 点，已按实际结果交换命名。

六个文件均为 512 × 512、RGBA 透明动画，共 181 帧，每帧 16 毫秒，原始总时长 2896 毫秒（约 62.5 fps）。按用户最新要求，以 WebP 原始速度播放，不额外减速。容器循环标记为 `loop=0`（无限循环），聊天渲染器需要自行控制播放一次、暂停及最终帧，不能直接依赖资源的循环标记。源文件透明像素不是黑色背景；应直接叠加到当前主题画布上。

| 点数 / 资源 | 用户附件顺序及原始文件 | 字节数 | 原始 SHA-256 |
| --- | --- | ---: | --- |
| 1 / `dice_1.webp` | 1 / `codex-clipboard-ca2cdaa1-99bc-46d2-a642-a206822aa5da.webp` | 1582746 | `39bf6f17967772da5e98d56693b4d685dd9aeff43f7a661f78c42c6238f10bb4` |
| 2 / `dice_2.webp` | 2 / `codex-clipboard-c1fad335-3d04-431f-883c-3ffef45ddedc.webp` | 1551368 | `22b6700e66a4dfae4662b882900df24df6774e16e91bf5983804824353325712` |
| 3 / `dice_3.webp` | 3 / `codex-clipboard-0fbe787a-cec4-4d97-aa7e-48863ad6f450.webp` | 1545684 | `6c38c5e7cdb9e21750e6053f6d55a0929c4ee0574d6815635a14c60dc46955ce` |
| 4 / `dice_4.webp` | 4 / `codex-clipboard-08090623-1a46-45aa-9c12-c883d871792d.webp` | 1573996 | `00e5fe7871d95f7a53db3a530bd6dcb1d6efcd14b90784f903f5b8c9e9cf9a71` |
| 5 / `dice_5.webp` | 6 / `codex-clipboard-b93a631e-d681-4243-b68d-bf5197f7ad4f.webp` | 1573866 | `941a54814be6efcd167049f71a28c1ebfa30abd909fb356223aae74fe3c36255` |
| 6 / `dice_6.webp` | 5 / `codex-clipboard-a038e37e-8a9f-4783-b7a9-71701a314a07.webp` | 1624300 | `d075ade3ac2553518ca32e95233903a7d76ed4320459c1df3d0e93fa778d9486` |

资源不需要网络加载。验证使用 Pillow 10.4.0 的 WebP 解码器逐帧解码、检查透明度、帧时长、末帧点数和原件与副本哈希。亮暗背景的末帧检查图及完整元数据位于工作区 `artifacts/chat-dice/dice-webp-source-final-light.png`、`dice-webp-source-final-dark.png`、`dice-webp-metadata.json`。这些检查图不作为生产资源使用。

## 静态结果资源

`dice_1_final.webp` 至 `dice_6_final.webp` 是从对应动画第 180 帧（最后一帧）的完整合成 RGBA 图像无损导出的单帧 WebP，尺寸仍为 512 × 512。用于表情入口、历史消息和静态结果，避免为了显示一个静态结果在运行时解码并上传整段 181 帧，减少与正在播放的动画争用解码队列。上表的六个原始动画文件没有修改，仍按每帧 16 毫秒播放。

导出使用 Pillow 的 `lossless=True`、`exact=True`，重新解码后逐像素比较 RGBA，与原动画完整合成末帧完全一致，包括透明像素。没有直接拆取末尾 ANMF 块，因为该块仅覆盖局部画布，需要此前帧才能合成完整骰子。详细校验记录位于 `artifacts/chat-dice/video-review/dice-final-poster-metadata.json`。

| 点数 / 静态资源 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 1 / `dice_1_final.webp` | 44384 | `b192586022e5da0e8872accda1b8489490be2be5f05a0fa8c97aba853423a3df` |
| 2 / `dice_2_final.webp` | 37134 | `de041c40f3ad6337c98212f8facfc8dcce04e1778e7b2521572db90abfc5d1c7` |
| 3 / `dice_3_final.webp` | 36760 | `cce7a103baf476c33def105a05757884357195352dd66fe3b57cf7dbc1d49bbd` |
| 4 / `dice_4_final.webp` | 42472 | `d6b2f2e9a225b4a3e41a5aead6db37cf265f923fbf4292e5f3ac55323f74bbff` |
| 5 / `dice_5_final.webp` | 39730 | `869957e3d0dafd766c986ffc68e1db571ac262fdd7b73e2547d197a923723a58` |
| 6 / `dice_6_final.webp` | 45894 | `113a29208b841d801a8b3584c1e0b2dd6e3fcfe0533d5ecca50c0fb53df7b782` |
