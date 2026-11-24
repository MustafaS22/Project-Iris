from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import json
root=Path('/tmp/IrisComputerValidation');root.mkdir(exist_ok=True)
p=root/'http-test.txt';p.write_text('HTTP real file contents')
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self): self.send_error(405)
 def do_DELETE(self): self.send_response(200);self.end_headers()
 def do_POST(self):
  obj=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  method=obj.get('method','');rid=obj.get('id')
  if rid is None: self.send_response(202);self.end_headers();return
  if method=='initialize': result={'protocolVersion':'2025-11-25','capabilities':{'tools':{},'resources':{},'prompts':{}},'serverInfo':{'name':'iris-real-file-test','version':'1.0'}}
  elif method=='tools/list': result={'tools':[{'name':'read_test_file','description':'Read the isolated test file from disk','inputSchema':{'type':'object','properties':{}}}]}
  elif method=='resources/list': result={'resources':[{'uri':'test://file','name':'Isolated test file','mimeType':'text/plain'}]}
  elif method=='prompts/list': result={'prompts':[{'name':'test-guide','description':'Explain an isolated test file'}]}
  elif method=='tools/call': result={'content':[],'structuredContent':{'text':p.read_text()}}
  elif method=='resources/read': result={'contents':[{'uri':'test://file','text':p.read_text(),'mimeType':'text/plain'}]}
  elif method=='prompts/get': result={'messages':[{'role':'user','content':{'type':'text','text':'Explain this local test file: '+p.read_text()}}]}
  else: result={}
  data=json.dumps({'jsonrpc':'2.0','id':rid,'result':result}).encode()
  self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1',5198),Handler).serve_forever()
