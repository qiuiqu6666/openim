"""Apply reviewed changes to a fresh staged server tree, never the live tree."""
from pathlib import Path
import shutil
root=Path('/home/ubuntu/media-upload-disaster-20261023/source')
assets=Path('/home/ubuntu/media-upload-disaster-20261023/assets')
for name in ['storage_route.go','storage_route_test.go']:
 shutil.copyfile(assets/name, root/'internal/rpc/third'/name)
p=root/'internal/rpc/third/third.go';s=p.read_text()
s=s.replace('s3dataBase    controller.S3Database','s3dataBase    controller.S3Database\n\tbackupStorage *backupStorage')
s=s.replace('store := controller.NewS3Database(rdb, o, s3db)', 'store := controller.NewS3Database(rdb, o, s3db)\n\tvar backup *backupStorage')
anchor='store = &legacyReadStore{S3Database: store, legacy: controller.NewS3Database(rdb, reader, s3db)}'
assert anchor in s
s=s.replace(anchor,anchor+'''
        if old.BucketURL == "https://99chat-1416337673.cos.ap-hongkong.myqcloud.com" {
            conf := *old.Build()
            conf.BucketURL = "https://99chat-1416337673.cos.accelerate.myqcloud.com"
            hk, err := objectstorage.NewCOSWithRuntime(ctx, conf, old.BucketURL, config.RpcConfig.Object.Upload, rdb)
            if err != nil { return err }
            var backend s3.Interface = hk
            if old.EngineName != "" { backend = &objectstorage.NamedEngine{Interface:hk, Name:old.EngineName} }
            backup = &backupStorage{store:controller.NewS3Database(rdb, backend, s3db), backend:backend}
        }
''')
s=s.replace('s3dataBase:    store,','s3dataBase:    store,\n\t\tbackupStorage: backup,')
p.write_text(s)
p=root/'internal/rpc/third/s3.go';s=p.read_text()
for method,typ in [('InitiateMultipartUpload','InitiateMultipartUpload'),('CompleteMultipartUpload','CompleteMultipartUpload'),('AccessURL','AccessURL'),('AuthSign','AuthSign')]:
 signature=f'func (t *thirdServer) {method}(ctx context.Context, req *third.{typ}Req) (*third.{typ}Resp, error) {{'
 assert signature in s
 name='req.Name' if method!='AuthSign' else '""'
 uid='req.UploadID' if method in ('AuthSign','CompleteMultipartUpload') else '""'
 code=f'\n routed, uploadID, routeErr := t.forUploadStorage({name}, {uid})\n if routeErr != nil {{ return nil, routeErr }}\n t = routed\n'
 if uid!='""': code+=' copyReq := *req\n copyReq.UploadID = uploadID\n req = &copyReq\n'
 else: code+=' _ = uploadID\n'
 s=s.replace(signature,signature+code)
# Prefix only the successful new session, not a hash-dedup URL.
anchor='\tvar sign *third.AuthSignParts'
assert anchor in s
s=s.replace(anchor,'\tif hongKongName(req.Name) { result.UploadID = hongKongUploadPrefix + result.UploadID }\n'+anchor)
for method,nextmethod in [('InitiateMultipartUpload','AuthSign'),('AuthSign','CompleteMultipartUpload'),('CompleteMultipartUpload','AccessURL')]:
 a=s.index('func (t *thirdServer) '+method+'(');b=s.index('func (t *thirdServer) '+nextmethod+'(',a)
 s=s[:a]+s[a:b].replace('return nil, err','return nil, storageAttemptError(err)')+s[b:]
p.write_text(s)
p=root/'pkg/common/storage/objectstorage/cos_upload_fallback.go' ;s=p.read_text()
s=s.replace('if strings.TrimRight(conf.BucketURL, "/") != acceleratedOrigin {\n\t\treturn nil, nil\n\t}\n\tconf.BucketURL, conf.CDN = regionalOrigin, ""', '''switch strings.TrimRight(conf.BucketURL, "/") {
 case acceleratedOrigin: conf.BucketURL = regionalOrigin
 case "https://99chat-1416337673.cos.accelerate.myqcloud.com": conf.BucketURL = "https://99chat-1416337673.cos.ap-hongkong.myqcloud.com"
 default: return nil, nil
 }
 conf.CDN = ""''')
p.write_text(s)
p=root/'internal/api/uploadrelay/relay.go';s=p.read_text()
s=s.replace('const MaxPartBytes', 'const HongKongHost = "99chat-1416337673.cos.ap-hongkong.myqcloud.com"\nconst MaxPartBytes')
s=s.replace('u.Host != RegionalHost', '(u.Host != RegionalHost && u.Host != HongKongHost)')
s=s.replace('target.Header.Get(key) != RegionalHost', 'target.Header.Get(key) != u.Host')
p.write_text(s)
p=root/'internal/api/uploadregion/region.go';s=p.read_text()
s=s.replace('target["preferRegional"] = json.RawMessage(flag)', 'target["preferRegional"] = json.RawMessage(flag)\n target["multiBucket"] = json.RawMessage("true")')
p.write_text(s)
print('staged server sources prepared')
