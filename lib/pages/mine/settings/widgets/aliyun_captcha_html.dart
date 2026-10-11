import 'dart:convert';

/// Only public scene configuration belongs in the client.
String aliyunCaptchaHtml({required String language}) => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;padding:0;background:transparent;}#captcha-button{display:none}</style>
</head><body><div id="captcha-element"></div><button id="captcha-button"></button>
<script>
window.AliyunCaptchaConfig={region:'sgp',prefix:'x8rp89e'};
let sequence=0,loadFailed=false,opening=false; const pending=new Map();
function post(message){CaptchaBridge.postMessage(JSON.stringify(message));}
function fail(){if(loadFailed)return;loadFailed=true;post({type:'error'});}
function openCaptcha(instance){
 if(loadFailed||opening)return;
 opening=true;window.captcha=instance;
 // Defer until the SDK's initialization callback has returned, not a fixed delay.
 setTimeout(function(){
  if(loadFailed)return;
  try{
   if(!window.captcha||typeof window.captcha.show!=='function'){fail();return;}
   Promise.resolve(window.captcha.show()).then(function(){
    if(!loadFailed)post({type:'ready'});
   },fail);
  }catch(e){fail();}
 },0);
}
window.resolveCaptchaRequest=function(id,result){const resolve=pending.get(id);if(resolve){pending.delete(id);resolve(result);}};
const script=document.createElement('script');
script.src='https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';
script.onerror=fail;
script.onload=function(){try{
 window.initAliyunCaptcha({
 SceneId:'11obe4txe',mode:'popup',element:'#captcha-element',button:'#captcha-button',
 language:${jsonEncode(language)},
 getInstance:openCaptcha,
 onClose:function(reason){post({type:'close',reason:reason});},
 onError:fail,
 captchaVerifyCallback:function(param){return new Promise(function(resolve){
 const id=++sequence;pending.set(id,resolve);post({type:'verify',id:id,captchaVerifyParam:param});});},
 onBizResultCallback:function(result){post({type:'complete',bizResult:result});}
 });
}catch(e){fail();}};
document.head.appendChild(script);
</script></body></html>
''';
