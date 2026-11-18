const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('iris', {call:(name,data)=>ipcRenderer.invoke('iris',name,data),on:(fn)=>{ipcRenderer.on('iris-event',(_,event)=>fn(event));}});
