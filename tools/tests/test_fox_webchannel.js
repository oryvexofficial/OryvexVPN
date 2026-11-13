const fs=require('fs'),vm=require('vm'),assert=require('assert');
const path=require('path').resolve(__dirname, '../../apps/shared/lib/src/ui/widgets/fox_web_signin.dart');
const contents=fs.readFileSync(path,'utf8');
const script=contents.match(/const _channelScript = r'''([\s\S]*?)''';/)[1];
function env(origin){
 let events={}, responses=[], calls=[];
 let win={addEventListener:(name,fn)=>events[name]=fn,dispatchEvent:(event)=>responses.push(event), flutter_inappwebview:{callHandler:(...a)=>{calls.push(a);return Promise.resolve()}}};
 win.top=win; let ctx={window:win,location:{origin},CustomEvent:function(type,opts){this.type=type;this.detail=opts.detail}}; vm.createContext(ctx); vm.runInContext(script,ctx);
 return {events,responses,calls};
}
let e=env('https://accounts.firefox.com');
e.events.WebChannelMessageToChrome({detail:{id:'account_updates',message:{command:'fxaccounts:fxa_status',messageId:12}}});
assert.equal(e.responses.length,1);assert.equal(e.responses[0].detail.message.messageId,12);assert.equal(e.responses[0].detail.message.data.signedInUser,null);
e.events.WebChannelMessageToChrome({detail:JSON.stringify({id:'account_updates',message:{command:'fxaccounts:can_link_account',messageId:13}})});
assert.equal(e.responses[1].detail.message.data.ok,true);
e.events.WebChannelMessageToChrome({detail:{id:'account_updates',message:{command:'fxaccounts:login',data:{email:'fixture@example.invalid',sessionToken:'bad'}}}});assert.equal(e.calls.length,0);
e.events.WebChannelMessageToChrome({detail:{id:'account_updates',message:{command:'fxaccounts:login',data:{email:'fixture@example.invalid',sessionToken:'a'.repeat(64)}}}});assert.equal(e.calls.length,1);assert.equal(e.calls[0][0],'firefoxAccountLogin');
assert(!env('https://example.invalid').events.WebChannelMessageToChrome);
console.log('WebChannel fixture tests passed: status, link response, token validation, and origin restriction.');
