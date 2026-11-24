from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import json,re,time
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_POST(self):
  obj=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  system=obj['messages'][0]['content'];goal=obj['messages'][-1]['content']
  if 'stop validation' in goal: time.sleep(5);decision={'done':True,'summary':'Stopped fixture'}
  else:
   folder=re.search(r'Computer test=([^,\n]+)',system).group(1).strip()
   path=re.search(r'file (loop-[^ ]+\.txt)',goal).group(1)
   history=system.split('RECENT ACTIONS:')[-1]
   if 'native/file_read:' in history: decision={'done':True,'summary':'Verified the isolated file contains the actual HTTP MCP file contents.'}
   elif 'native/file_write:' in history: decision={'tool':'file_read','server':'native','arguments':{'folder':folder,'path':path},'reason':'Read the isolated file to verify its exact contents'}
   elif 'read_test_file:' not in history and 'native/get_active_window:' in history:
    server=re.search(r'([A-Fa-f0-9-]{36})/read_test_file',system).group(1)
    decision={'tool':'read_test_file','server':server,'arguments':{},'reason':'Read the isolated HTTP MCP file'}
   elif 'native/get_active_window:' not in history: decision={'tool':'get_active_window','server':'native','arguments':{},'reason':'Inspect the active native application'}
   else: decision={'tool':'file_write','server':'native','arguments':{'folder':folder,'path':path,'content':'HTTP real file contents'},'reason':'Create the isolated test file'}
  data=json.dumps({'choices':[{'message':{'role':'assistant','content':json.dumps(decision)}}]}).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers()
  try:self.wfile.write(data)
  except BrokenPipeError:pass
ThreadingHTTPServer(('127.0.0.1',5196),Handler).serve_forever()
