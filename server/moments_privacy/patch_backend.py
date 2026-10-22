from pathlib import Path
import sys
root=Path(sys.argv[1])
def edit(name,old,new):
 p=root/name;s=p.read_bytes();old=old.encode();new=new.encode();assert old in s,name;p.write_bytes(s.replace(old,new,1))
edit('pkg/common/db/table/chat/moment.go','type MomentSettings struct {','type MomentSettings struct {\n\tUpdatedAt int64 `bson:"updated_at"`')
p=root/'pkg/protocol/chat/chat.proto';s=p.read_bytes();start=s.index(b'message MomentSettingsResp {');end=s.index(b'}',start);block=s[start:end];nl=b'\r\r\n' if b'\r\r\n' in block else b'\n';s=s[:end]+nl.join([b'  repeated string blockedViewerIDs = 6;',b'  repeated string hiddenAuthorIDs = 7;',b'  int64 updatedAt = 8;',b'  bool privacyListsLoaded = 9;',b''])+s[end:];p.write_bytes(s)
edit('pkg/common/db/database/moment.go','\tvar row *chatdb.MomentSettings\n\terr := d.tx.Transaction(ctx, func(ctx context.Context) error {\n\t\tcurrent, err := d.store.TakeSettings(ctx, userID)','\tfieldsCopy := make(map[string]any, len(fields)+1)\n\tfor key, value := range fields { fieldsCopy[key] = value }\n\tfields = fieldsCopy\n\tfields["updated_at"] = now.UnixMilli()\n\tvar row *chatdb.MomentSettings\n\terr := d.tx.Transaction(ctx, func(ctx context.Context) error {\n\t\tcurrent, err := d.store.TakeSettings(ctx, userID)')
edit('pkg/common/db/database/moment.go','\t\t_ = now\n','')
edit('pkg/common/db/database/moment.go','switch key {\n\tcase "visible_range_days":','switch key {\n\tcase "updated_at":\n\t\trow.UpdatedAt, _ = value.(int64)\n\tcase "visible_range_days":')
edit('pkg/common/db/database/moment.go','row = &chatdb.MomentSettings{UserID: userID, Version: version}','row = &chatdb.MomentSettings{UserID: userID, Version: version}\n\t\t\tif changed { row.UpdatedAt = time.Now().UTC().UnixMilli() }')
edit('pkg/common/db/database/moment.go','ok, err := d.store.UpdateSettings(ctx, userID, current.Version, map[string]any{}, current.Version+1)','updatedAt := time.Now().UTC().UnixMilli()\n\t\tok, err := d.store.UpdateSettings(ctx, userID, current.Version, map[string]any{"updated_at": updatedAt}, current.Version+1)')
edit('pkg/common/db/database/moment.go','row.Version = current.Version + 1\n','row.Version = current.Version + 1\n\t\trow.UpdatedAt = updatedAt\n')
# Read the lists and settings inside one database transaction, just like writes.
p=root/'pkg/common/db/database/moment.go';s=p.read_text();s+='''
// SettingsSnapshot returns only the authenticated owner's settings and lists.
func (d *MomentDatabase) SettingsSnapshot(ctx context.Context, userID string) (row *chatdb.MomentSettings, blocked, hidden []string, err error) {
 err = d.tx.Transaction(ctx, func(ctx context.Context) error {
  var readErr error
  row, readErr = d.store.TakeSettings(ctx, userID)
  if d.missing(readErr) { row = &chatdb.MomentSettings{UserID: userID} } else if readErr != nil { return readErr }
  blocked, readErr = d.store.ListBlockedViewers(ctx, userID)
  if readErr != nil { return readErr }
  hidden, readErr = d.store.ListHiddenAuthors(ctx, userID)
  return readErr
 })
 return
}
''';p.write_text(s)
p=root/'internal/rpc/chat/moment.go';s=p.read_text();start=s.index('\trow, err := o.Moments.Store().TakeSettings(ctx, viewer)',s.index('func (o *chatSvr) settingsResp'));end=s.index('\tversion, err := o.feedVersion',start);s=s[:start]+'''\trow, blocked, hidden, err := o.Moments.SettingsSnapshot(ctx, viewer)
 if err != nil { return nil, err }
 sort.Strings(blocked)
 sort.Strings(hidden)
'''+s[end:];needle='ViewerContextVersion: version}';start=s.index(needle,s.index('func (o *chatSvr) settingsResp'));s=s[:start]+s[start:].replace(needle,'ViewerContextVersion: version, BlockedViewerIDs: blocked, HiddenAuthorIDs: hidden, UpdatedAt: row.UpdatedAt, PrivacyListsLoaded: true}',1);p.write_text(s)
print('Patched isolated source')
