<template>
  <el-space direction="vertical" fill style="width:100%">
    <el-card>
      <el-form inline @submit.prevent="load(1)">
        <el-form-item label="投诉人"><el-input v-model="query.userID" clearable /></el-form-item>
        <el-form-item label="被投诉人"><el-input v-model="query.reportedUserID" clearable /></el-form-item>
        <el-form-item label="群 ID"><el-input v-model="query.groupID" clearable /></el-form-item>
        <el-form-item label="聊天类型"><el-select v-model="query.chatType" clearable style="width:120px"><el-option label="单聊" value="c2c"/><el-option label="群聊" value="group"/></el-select></el-form-item>
        <el-form-item label="原因"><el-select v-model="query.reason" clearable style="width:140px"><el-option v-for="(label,key) in reasons" :key="key" :value="key" :label="label"/></el-select></el-form-item>
        <el-form-item label="状态"><el-select v-model="query.status" clearable style="width:120px"><el-option v-for="(label,key) in statuses" :key="key" :value="key" :label="label"/></el-select></el-form-item>
        <el-form-item><el-button type="primary" native-type="submit" :loading="loading">查询</el-button></el-form-item>
      </el-form>
      <admin-table :data="rows" v-loading="loading" empty-text="暂无投诉记录">
        <el-table-column prop="complaintID" label="投诉 ID" min-width="230"/>
        <el-table-column label="投诉人" min-width="200"><template #default="{row}"><div class="complaint-identity"><strong>{{row.userNickname||("名称暂不可用")}}</strong><small>{{row.userID||'—'}}</small></div></template></el-table-column>
        <el-table-column label="类型" width="80"><template #default="{row}">{{row.chatType==='group'?'群聊':'单聊'}}</template></el-table-column>
        <el-table-column label="被投诉人" min-width="200"><template #default="{row}"><div class="complaint-identity"><strong>{{row.reportedUserNickname||("名称暂不可用")}}</strong><small>{{row.reportedUserID||'—'}}</small></div></template></el-table-column>
        <el-table-column label="群聊" min-width="200"><template #default="{row}"><div class="complaint-identity"><strong>{{row.groupName||(row.groupID ? "名称暂不可用" : "—")}}</strong><small>{{row.groupID||'—'}}</small></div></template></el-table-column>
        <el-table-column label="原因" width="110"><template #default="{row}">{{reasons[row.reason]||row.reason}}</template></el-table-column>
        <el-table-column label="状态" width="100"><template #default="{row}">{{statuses[row.status]||row.status}}</template></el-table-column>
        <el-table-column label="时间" min-width="180"><template #default="{row}">{{date(row.createdAt)}}</template></el-table-column>
        <el-table-column label="操作" width="90"><template #default="{row}"><el-button link type="primary" @click="open(row)">查看</el-button></template></el-table-column>
      </admin-table>
      <el-pagination style="margin-top:16px" layout="total, prev, pager, next" :total="total" :page-size="20" :current-page="page" @current-change="load"/>
    </el-card>
    <el-dialog v-model="visible" title="投诉详情" width="min(860px, 96vw)">
      <div v-loading="detailLoading">
        <el-descriptions v-if="detail.complaintID" :column="2" border>
          <el-descriptions-item label="投诉 ID">{{detail.complaintID}}</el-descriptions-item>
          <el-descriptions-item label="类型">{{detail.chatType==='group'?'群聊':'单聊'}}</el-descriptions-item>
          <el-descriptions-item label="投诉人"><div class="complaint-identity"><strong>{{detail.userNickname||"名称暂不可用"}}</strong><small>{{detail.userID||'—'}}</small></div></el-descriptions-item>
          <el-descriptions-item label="被投诉人"><div class="complaint-identity"><strong>{{detail.reportedUserNickname||"名称暂不可用"}}</strong><small>{{detail.reportedUserID||'—'}}</small></div></el-descriptions-item>
          <el-descriptions-item label="群 ID"><div class="complaint-identity"><strong>{{detail.groupName||(detail.groupID ? "名称暂不可用" : "—")}}</strong><small>{{detail.groupID||'—'}}</small></div></el-descriptions-item>
          <el-descriptions-item label="原因">{{reasons[detail.reason]}}</el-descriptions-item>
          <el-descriptions-item label="提交时间">{{date(detail.createdAt)}}</el-descriptions-item>
          <el-descriptions-item label="客户端版本">{{detail.clientVersion||'—'}}</el-descriptions-item>
          <el-descriptions-item label="补充说明" :span="2"><span style="white-space:pre-wrap;overflow-wrap:anywhere">{{detail.content||'无'}}</span></el-descriptions-item>
          <el-descriptions-item label="处理人">{{detail.reviewedBy||'—'}}</el-descriptions-item>
          <el-descriptions-item label="更新时间">{{date(detail.updatedAt)}}</el-descriptions-item>
        </el-descriptions>
        <el-space wrap style="margin:16px 0"><el-image v-for="(shot,i) in detail.screenshots||[]" :key="i" :src="shot.url" :preview-src-list="(detail.screenshots||[]).map(s=>s.url)" :initial-index="i" preview-teleported fit="cover" style="width:120px;height:120px"/></el-space>
        <el-form v-if="detail.complaintID" label-width="80px">
          <el-form-item label="处理状态"><el-select v-model="edit.status"><el-option v-for="(label,key) in statuses" :key="key" :value="key" :label="label"/></el-select></el-form-item>
          <el-form-item label="处理备注"><el-input v-model="edit.note" type="textarea" :rows="4" maxlength="2000" show-word-limit/></el-form-item>
          <el-form-item><el-button type="primary" :loading="saving" @click="save">保存处理结果</el-button></el-form-item>
        </el-form>
        <el-button v-else-if="!detailLoading" @click="open(selected)">加载失败，重试</el-button>
      </div>
    </el-dialog>
  </el-space>
</template>
<script setup>
import { ref, reactive, watch, onBeforeUnmount } from 'vue';
import { useAuthStore } from '../stores/auth';
import { ElMessage } from 'element-plus';
import { api, page as pagination } from '../api/http';
const reasons={spam:'垃圾信息',harassment:'骚扰辱骂',fraud:'诈骗',pornography:'色情低俗',violence:'暴力威胁',illegal:'违法违规',other:'其他'};
const statuses={received:'已收到',processing:'处理中',resolved:'已处理',rejected:'已驳回'};
const rows=ref([]),total=ref(0),page=ref(1),loading=ref(false),visible=ref(false),detailLoading=ref(false),saving=ref(false),detail=ref({});
const query=reactive({userID:'',reportedUserID:'',groupID:'',chatType:'',reason:'',status:''}),edit=reactive({status:'received',note:''});
let selected=null,loadRevision=0,detailRevision=0;
const objectURLs=new Set();
function clearURLs(){for(const url of objectURLs)URL.revokeObjectURL(url);objectURLs.clear();}
watch(visible,value=>{if(!value){++detailRevision;clearURLs();}});
onBeforeUnmount(()=>{++detailRevision;clearURLs();});
async function screenshots(data,revision){
 clearURLs();
 await Promise.all((data.screenshots||[]).map(async(shot,index)=>{
  const response=await fetch('/complaints/screenshot',{method:'POST',credentials:'omit',headers:{'Content-Type':'application/json',token:useAuthStore().token,operationID:crypto.randomUUID()},body:JSON.stringify({complaintID:data.complaintID,index})});
  if(!response.ok||!(response.headers.get('content-type')||'').startsWith('image/'))throw new Error('截图加载失败，请重新打开详情重试');
  const blob=await response.blob();if(revision!==detailRevision)return;
  const url=URL.createObjectURL(blob);objectURLs.add(url);shot.url=url;
 }));
}
const date=v=>v?new Date(v).toLocaleString():'—';
async function load(p=page.value){const revision=++loadRevision;loading.value=true;page.value=p;try{const data=await api('/complaints/search',{...query,pagination:pagination(p,20)});if(revision===loadRevision){rows.value=data.complaints||[];total.value=data.total||0;}}catch(e){ElMessage.error(e.message||'加载失败');}finally{if(revision===loadRevision)loading.value=false;}}
async function open(row){if(!row)return;clearURLs();selected=row;const revision=++detailRevision;visible.value=true;detail.value={};detailLoading.value=true;try{const data=await api('/complaints/detail',{complaintID:row.complaintID});if(revision!==detailRevision)return;detail.value=data;edit.status=data.status;edit.note=data.note||'';await screenshots(data,revision);}catch(e){ElMessage.error(e.message||'详情加载失败');}finally{if(revision===detailRevision)detailLoading.value=false;}}
async function save(){if(saving.value)return;const id=detail.value.complaintID;saving.value=true;try{const data=await api('/complaints/update',{complaintID:id,...edit});if(detail.value.complaintID===id)detail.value={...detail.value,...data,screenshots:detail.value.screenshots};ElMessage.success('已保存');await load();}catch(e){ElMessage.error(e.message||'保存失败');}finally{saving.value=false;}}
load(1);
</script>

<style scoped>
.complaint-identity { display:flex; flex-direction:column; gap:4px; overflow-wrap:anywhere; line-height:1.5; }
.complaint-identity strong { font-weight:500; color:var(--el-text-color-primary); }
.complaint-identity small { font-size:12px; color:var(--el-text-color-secondary); }
</style>
