// Scratch daemon for the iPhone UI test testSendNowStopAndTerminalView. Own HOME, data dir,
// port and tmux socket; never the user's daemon, panes or ~/.claude* dirs.
// Run: cd context-find/ts && node --loader ./test/typescript-loader.mjs <this> $PWD
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, realpathSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { createInterface } from "node:readline";
import { join } from "node:path";
import { tmpdir } from "node:os";

const home = realpathSync(mkdtempSync(join(tmpdir(), "cfind-phone-")));
const socket = "cfind-phone-" + process.pid;
const work = join(home, "work"), bin = join(home, "bin");
const keysLog = join(home, "keys.txt");
mkdirSync(work); mkdirSync(bin);
Object.assign(process.env, {
  HOME: home,
  CFIND_DATA_DIR: join(home, "data"),
  CODEX_HOME: join(home, "codex"),
  CFIND_CLAUDE_BIN: join(bin, "claude"),
  CFIND_TMUX_BIN: join(bin, "tmux"),
  // Keeps the real tailnet name out of the scratch data dir.
  CFIND_TAILSCALE_BIN: "/usr/bin/false",
});
delete process.env.CLAUDE_CONFIG_DIR;
delete process.env.TMUX;

const tmux = (...args) => execFileSync("tmux", ["-L", socket, ...args], { encoding: "utf8" }).trim();
writeFileSync(join(bin, "tmux"), `#!/bin/sh\nexec tmux -L ${socket} "$@"\n`, { mode: 0o700 });

// Dashboard agents: "slow" prompts take 60 s; the interrupt control request ends the turn.
writeFileSync(join(bin, "claude"), `#!/usr/bin/env node
const send=o=>console.log(JSON.stringify(o));let timer,mode='default';
require('node:readline').createInterface({input:process.stdin}).on('line',line=>{
 const m=JSON.parse(line);
 if(m.type==='control_request'){const r=m.request;
  if(r.subtype==='interrupt'){clearTimeout(timer);
   send({type:'control_response',response:{subtype:'success',request_id:m.request_id,response:{still_queued:[]}}});
   send({type:'result',subtype:'success',is_error:false,result:''});return;}
  if(r.subtype==='set_permission_mode'){mode=r.mode;
   send({type:'control_response',response:{subtype:'success',request_id:m.request_id,response:{mode}}});
   send({type:'system',subtype:'status',permissionMode:mode});return;}
  send({type:'control_response',response:{subtype:'success',request_id:m.request_id,response:{}}});return;}
 if(m.type!=='user')return;const c=m.message.content,text=typeof c==='string'?c:c.map(x=>x.text||'').join(' ');
 send({type:'system',subtype:'init',session_id:'agent-'+process.pid,model:'opus',permissionMode:mode});
 timer=setTimeout(()=>{send({type:'assistant',message:{id:'r'+Math.random(),content:[{type:'text',text:'reply to '+text}]}});send({type:'result',subtype:'success',is_error:false,result:'done'});},text.includes('slow')?60000:300);
});`, { mode: 0o700 });

// The terminal session drives itself from the keys it gets, like Claude's TUI:
// a question menu (waiting), then a reply (running), then the prompt (idle). It
// rewrites its own live record, so the daemon sees each state change.
writeFileSync(join(bin, "menu.js"), `
const fs=require('node:fs'),path=require('node:path');
const log=process.env.KEYS_LOG,dir=process.env.LIVE_DIR,transcript=process.env.TRANSCRIPT,sid=process.env.SID;
const opts=['Red','Blue'];let at=0,mode='menu',input='',lines=[],pend='',esc=false,lastByte='';
const setState=(status)=>{for(const n of fs.readdirSync(dir)){const f=path.join(dir,n);try{const r=JSON.parse(fs.readFileSync(f,'utf8'));
 if(r.sessionId===sid)fs.writeFileSync(f,JSON.stringify({...r,status,updatedAt:Date.now()}));}catch{}}};
const say=(t)=>{lines.push(t);lines=lines.slice(-15);};
const draw=()=>{const body=mode==='menu'
 ?['Pick a colour',...opts.map((o,i)=>(i===at?'❯ ':'  ')+(i+1)+'. '+o),'','Enter to select · Esc to cancel']
 :[...lines,'','> '+input];
 process.stdout.write('\\x1b[2J\\x1b[H'+['Claude Code (test)','',...body].join('\\r\\n'));};
const run=(status,text)=>{mode=status;setState(status==='running'?'busy':status);if(text)say(text);};
const handle=(k)=>{
 if(mode==='menu'){
  if(k==='up')at=Math.max(0,at-1);else if(k==='down')at=Math.min(opts.length-1,at+1);
  else if(k==='enter'){say('Picked '+opts[at]);run('running','Working…');}
  else if(k==='esc')run('idle','Cancelled');
  return;}
 if(k==='send-now'){say('Sent now');return;}
 if(k==='esc'){esc=mode==='running';return;}
 if(k==='clear'){input='';return;}
 if(k==='back'){if(esc&&lastByte==='clear'){esc=false;run('idle','Stopped');}else input=input.slice(0,-1);return;}
 if(k==='enter'){if(!input)return;const t=input;input='';say('Got: '+t);
  fs.appendFileSync(transcript,JSON.stringify({type:'user',uuid:'t'+Date.now(),sessionId:sid,cwd:process.cwd(),timestamp:new Date().toISOString(),message:{role:'user',content:t}})+'\\n');
  if(mode==='idle')run('running','Working…');return;}
 if(typeof k==='object')input+=k.text;};
const keys=(s)=>{const out=[];for(let i=0;i<s.length;){const r=s.slice(i);
 if(/^\\x1b(\\[|O)A/.test(r)){out.push('up');i+=3;}else if(/^\\x1b(\\[|O)B/.test(r)){out.push('down');i+=3;}
 else if(/^\\x1b\\[[CD]/.test(r)){i+=3;}
 else if(r.startsWith('\\x1b[200~')||r.startsWith('\\x1b[201~')){i+=6;}
 else if(r[0]==='\\x1b'){out.push('esc');i++;}
 else if(r.startsWith('\\x18\\x13')){out.push('send-now');i+=2;}
 else if(r[0]==='\\x18'){pend='\\x18';i++;}
 else if(r[0]==='\\x13'&&pend){pend='';out.push('send-now');i++;}
 else if(r[0]==='\\r'||r[0]==='\\n'){out.push('enter');i++;}
 else if(r[0]==='\\x15'){out.push('clear');i++;}
 else if(r[0]==='\\x7f'||r[0]==='\\b'){out.push('back');i++;}
 else if(r[0]>=' '){let j=i;while(j<s.length&&s[j]>=' '&&s[j]!=='\\x7f')j++;out.push({text:s.slice(i,j)});i=j;}
 else i++;}
 return out;};
// The harness's reset command puts the menu back.
process.on('SIGUSR1',()=>{mode='menu';at=0;input='';lines=[];esc=false;setState('waiting');draw();});
process.stdin.setRawMode(true);
process.stdin.on('data',d=>{fs.appendFileSync(log,d.toString('hex')+' ');
 for(const k of keys(d.toString())){handle(k);lastByte=typeof k==='string'?k:'text';}draw();});
draw();`);

const sid = "11111111-2222-4333-8444-555555555555";
const projects = join(home, ".claude", "projects", work.replace(/[^a-zA-Z0-9]/g, "-"));
mkdirSync(projects, { recursive: true });
mkdirSync(join(home, ".claude", "sessions"));
const now = Date.now(), at = (ms) => new Date(now - ms).toISOString();
const entry = (type, content, ms, extra = {}) =>
  JSON.stringify({ type, uuid: "u" + Math.random().toString(36).slice(2), sessionId: sid, cwd: work, timestamp: at(ms), message: { role: type, content, ...extra } });
writeFileSync(join(projects, sid + ".jsonl"), [
  entry("user", "Terminal test", 60000),
  entry("assistant", [{ type: "text", text: "Which colour should the button be?" }], 50000, { id: "a1", model: "claude-opus-5-5" }),
].join("\n") + "\n");

const transcript = join(projects, sid + ".jsonl"), liveDir = join(home, ".claude", "sessions");
const paneEnv = { KEYS_LOG: keysLog, LIVE_DIR: liveDir, TRANSCRIPT: transcript, SID: sid };
const [pane, pidText] = tmux("new-session", "-d", "-s", "harness", "-x", "100", "-y", "30", "-P", "-F", "#{pane_id} #{pane_pid}", "-c", work,
  ...Object.entries(paneEnv).flatMap(([k, v]) => ["-e", `${k}=${v}`]), process.execPath, join(bin, "menu.js")).split(" ");
const pid = Number(pidText);
const { procStart } = await import(process.argv[2] + "/src/live.ts");
const record = join(home, ".claude", "sessions", pid + ".json");
const setState = (status) =>
  writeFileSync(record, JSON.stringify({ pid, sessionId: sid, cwd: work, procStart: procStart(pid), tmux: `harness:@0.${pane}`, status, updatedAt: Date.now() }));
setState("waiting");

const { createWebServer } = await import(process.argv[2] + "/src/web.ts");
const { server, token, workspace } = createWebServer([]);
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;
const post = (path, body) =>
  fetch(`${base}/api/${path}?t=${token}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) })
    .then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(j.error || r.status); return j; });
const newAgent = () => post("agent", { action: "create", profile: "claude", cwd: work, prompt: "slow task" }).then((a) => a.id);
const newCode = () => post("devices", { action: "pair-start" }).then((p) => p.code);

let closed = false;
const cleanup = () => {
  if (closed) return;
  closed = true;
  try { workspace.close(); } catch {}
  try { server.closeAllConnections(); server.close(); } catch {}
  spawnSync("tmux", ["-L", socket, "kill-server"]);
  // tmux leaves the socket file behind when its server is killed.
  rmSync(join(process.env.TMUX_TMPDIR || "/tmp", `tmux-${process.getuid()}`, socket), { force: true });
  rmSync(home, { recursive: true, force: true });
};
process.on("SIGINT", () => { cleanup(); process.exit(0); });
process.on("SIGTERM", () => { cleanup(); process.exit(0); });
process.on("exit", cleanup);

const agentId = await newAgent();
console.log(JSON.stringify({ base, code: await newCode(), token, keysLog, sid, profile: "claude", agentId }));

createInterface({ input: process.stdin }).on("line", async (line) => {
  const [cmd, ...rest] = line.trim().split(" ");
  try {
    if (cmd === "reset" || (cmd === "state" && rest[0] === "waiting")) { process.kill(pid, "SIGUSR1"); console.log("reset"); }
    else if (cmd === "state") { setState(rest[0] === "running" ? "busy" : rest[0]); console.log("state " + rest[0]); }
    else if (cmd === "keys") console.log("keys " + (existsSync(keysLog) ? readFileSync(keysLog, "utf8").trim() : ""));
    else if (cmd === "agent") console.log("agent " + (await newAgent()));
    else if (cmd === "queue") { await post("agent", { action: "send", id: rest[0], prompt: rest.slice(1).join(" ") }); console.log("queued"); }
    else if (cmd === "code") console.log("code " + (await newCode()));
    else if (cmd === "screen") console.log(tmux("capture-pane", "-p", "-t", pane));
    else if (cmd) console.log("unknown " + cmd);
  } catch (e) { console.log("error " + e.message); }
});
