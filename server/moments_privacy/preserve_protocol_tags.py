from pathlib import Path
import re,sys
baseline=Path(sys.argv[1]);generated=Path(sys.argv[2])
old=baseline.read_text();new=generated.read_text()
def fields(text):
 result={}
 for name,body in re.findall(r'type (\w+) struct \{(.*?)\n\}',text,re.S):
  for field,typ,pb,js in re.findall(r'\n\s*(\w+)\s+([^\n`]+)`protobuf:"([^"]+)" json:"([^"]+)"`',body):
   result[(name,field)]=(typ.strip(),pb,js)
 return result
previous=fields(old);current=fields(new)
for key,(typ,pb,js) in previous.items():
 assert key in current,('removed field',key)
 assert current[key][:2]==(typ,pb),('changed existing field',key,current[key][:2],(typ,pb))
def fix_struct(m):
 name,body=m.group(1),m.group(2)
 def fix_field(f):
  key=(name,f.group(1));js=previous[key][2] if key in previous else f.group(3).replace(',omitempty','')
  return f.group(0).replace('json:"'+f.group(3)+'"','json:"'+js+'"')
 body=re.sub(r'\n\s*(\w+)\s+[^\n`]+`protobuf:"([^"]+)" json:"([^"]+)"`',fix_field,body)
 return 'type '+name+' struct {'+body+'\n}'
new=re.sub(r'type (\w+) struct \{(.*?)\n\}',fix_struct,new,flags=re.S)
generated.write_text(new)
print('Preserved',len(previous),'existing protobuf fields and JSON tags; added',len(current)-len(previous))
