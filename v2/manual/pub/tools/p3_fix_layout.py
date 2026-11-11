"""Long left-to-right chains were scaled down until unreadable: lay them out top to bottom."""
from edit import Doc

NL = "\n"
Doc("05-e4").replace('flowchart LR' + NL + '  P["Pod 的 CPU 用量', 'flowchart TB' + NL + '  P["Pod 的 CPU 用量').save()
Doc("06-e5").replace('flowchart LR' + NL + '  U["请求<br/>kubectl', 'flowchart TB' + NL + '  U["请求<br/>kubectl').save()
Doc("07-e6").replace('flowchart LR' + NL + '  C["调用方<br/>例如 orders"]', 'flowchart TB' + NL + '  C["调用方<br/>例如 orders"]').save()
