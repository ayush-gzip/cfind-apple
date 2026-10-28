// Records live-stream frames from the real encoder (context-find ts/src/delta.ts)
// for the Swift merge test in cfind-apple.
import { writeFileSync } from "node:fs";
const { Deltas } = await import(process.argv[2]);
const wire = (o: unknown) => JSON.parse(JSON.stringify(o));
const session = (id: string, updatedAt: number, extra: object = {}) => ({
  id, profile: "claude", source: "claude", path: `/home/u/.claude/projects/p/${id}.jsonl`, cwd: "/work/p",
  title: "Task " + id, updatedAt, state: "idle", tokens: { input: 1 }, ...extra,
});
const sessions = [session("s1", 100, { open: true, tmux: true }), session("s2", 90, { parent: "s1" }), session("s3", 80)];
const profiles: any[] = [
  { id: "claude", label: "Claude", source: "claude", path: "/x", tokens: { input: 5 } },
  { id: "personal", label: "Personal", source: "claude", path: "/y", tokens: { input: 2 } },
];
let clock = 1;
const sorted = () => [...sessions].sort((a, b) => b.updatedAt - a.updatedAt || (a.path < b.path ? -1 : 1));
const metrics = () => wire({ updatedAt: clock++, collecting: false, profiles, sessions: sorted(), days: [], models: [], usage: [], activity: [], costs: [], errors: [] });
const msg = (id: string, role: string, text: string, extra: object = {}) => ({ id, role, text, time: 1000, ...extra });
const a1: any = { id: "a1", profile: "claude", cwd: "/work/p", title: "Fix bug", state: "running", startedAt: 10, updatedAt: 11,
  messages: [msg("m1", "user", "fix it"), msg("m2", "assistant", "Hel")], queue: [], children: [] };
const agents: any[] = [a1];
const workspace = () => wire({ agents, logins: [] });

const frames: any[] = [];
const m = new Deltas(), w = new Deltas();
const step = (name: "metrics" | "workspace") => {
  const snap = name === "metrics" ? metrics() : workspace(),
    d = (name === "metrics" ? m : w).next(snap);
  if (!frames.some((f) => f.event === name)) frames.push({ event: name, data: snap, expect: snap });
  else if (d) frames.push({ event: name + "-delta", data: d, expect: snap,
    quiet: name === "metrics" && !d.set?.profiles && !d.set?.sessions && !d.lists?.sessions });
};
step("metrics"); step("workspace");
step("metrics"); // only the clock moves
Object.assign(sessions[2]!, { updatedAt: 120, state: "running" }); delete (sessions[0] as any).open; step("metrics");
sessions.push(session("s4", 120)); sessions.splice(1, 1); step("metrics");
profiles[0].limits = { plan: "max", session: { used: 42.5, resetsAt: 1900000000 } }; step("metrics");
sessions.splice(0, sessions.length); step("metrics");

a1.messages[1].text += "lo 🙂"; a1.updatedAt = 12; step("workspace");
a1.state = "waiting"; a1.pending = { id: 7, method: "can_use_tool", params: { tool_name: "Write" } }; step("workspace");
delete a1.pending; a1.state = "running"; a1.messages.push(msg("m3", "tool", "ls", { tool: { name: "Bash", input: "ls" } })); step("workspace");
a1.messages[2].tool.output = "a\nb"; step("workspace");
agents.unshift({ id: "a2", profile: "personal", cwd: "/w", title: "New", state: "queued", startedAt: 20, updatedAt: 20, messages: [], queue: [], children: [] }); step("workspace");
a1.messages = a1.messages.slice(1); a1.error = "Exited"; step("workspace");
agents.splice(0, 1); a1.messages[0].text += " more"; a1.queue.push({ text: "then test" }); step("workspace");
agents.push(agents.shift()!); a1.model = "sonnet"; delete a1.error; step("workspace");
writeFileSync(process.argv[3], JSON.stringify({ frames }, null, 1) + "\n");
console.log(frames.map((f) => f.event + (f.quiet ? " (quiet)" : "")).join(", "));
