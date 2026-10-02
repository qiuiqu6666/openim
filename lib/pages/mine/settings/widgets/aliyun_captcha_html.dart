import 'dart:convert';

/// Only public scene configuration belongs in the client.
String aliyunCaptchaHtml({required String language}) => '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;padding:0;background:transparent;}#captcha-button{display:none}</style>
</head><body><div id="captcha-element"></div><button id="captcha-button"></button>
<script>
window.AliyunCaptchaConfig={region:'sgp',prefix:'x8rp89e'};
let sequence=0,loadFailed=false; const pending=new Map();
function post(message){CaptchaBridge.postMessage(JSON.stringify(message));}
window.resolveCaptchaRequest=function(id,result){const resolve=pending.get(id);if(resolve){pending.delete(id);resolve(result);}};
const script=document.createElement('script');
script.src='https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js';
script.onerror=function(){post({type:'error'});};
script.onload=function(){try{
 window.initAliyunCaptcha({
 SceneId:'11obe4txe',mode:'popup',element:'#captcha-element',button:'#captcha-button',
 language:${jsonEncode(language)},
 getInstance:function(instance){window.captcha=instance;},
 onClose:function(reason){post({type:'close',reason:reason});},
 onError:function(){loadFailed=true;post({type:'error'});},
 captchaVerifyCallback:function(param){return new Promise(function(resolve){
 const id=++sequence;pending.set(id,resolve);post({type:'verify',id:id,captchaVerifyParam:param});});},
 onBizResultCallback:function(result){post({type:'complete',bizResult:result});}
 });
 setTimeout(function(){if(loadFailed)return;post({type:'ready'});window.captcha.show();},2100);
}catch(e){post({type:'error'});}};
document.head.appendChild(script);
</script></body></html>
''';
