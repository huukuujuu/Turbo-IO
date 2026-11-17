// Run on the bridge PC. Only fixed connection-test prompts are sent.
// No tokens, user prompts, user answers, or account details are printed.
import { readFileSync } from 'node:fs';
import { randomUUID, createHash } from 'node:crypto';

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index < 0 ? fallback : args[index + 1];
};
const endpoint = new URL(option('--endpoint', 'http://127.0.0.1:8787'));
if (endpoint.username || endpoint.password || endpoint.search || endpoint.hash ||
    !['http:', 'https:'].includes(endpoint.protocol) ||
    (endpoint.protocol === 'http:' && !['localhost', '127.0.0.1', '[::1]'].includes(endpoint.hostname))) {
  throw new Error('Use localhost HTTP or a credential-free HTTPS endpoint.');
}
const token = readFileSync(option('--token-file', './access-token'), 'utf8').trim();
const headers = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };
async function call(path, body) {
  const response = await fetch(new URL(path, endpoint), {
    method: body ? 'POST' : 'GET', headers,
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(40_000), redirect: 'error'
  });
  if (!response.ok) throw new Error('HTTP_' + response.status);
  return response.json();
}
const pause = () => new Promise(resolve => setTimeout(resolve, 1500));
async function trial(label, taskId) {
  const expected = 'TURBO_' + label + '_' + randomUUID().slice(0, 8);
  const requestId = randomUUID();
  // One POST only. Never retry a mutation whose delivery is uncertain.
  const receipt = await call('/v1/message', {
    requestId, ...(taskId ? { taskId } : {}),
    text: '연결 진단입니다. 파일을 읽거나 수정하거나 도구를 사용하지 마세요. 이전 응답을 반복하지 말고 다음 문구만 그대로 답하세요: ' + expected
  });
  if (receipt.accepted !== true || typeof receipt.taskId !== 'string') throw new Error('invalid_receipt');
  console.log(JSON.stringify({ stage: label, accepted: true, task: receipt.taskId.slice(0, 8), request: requestId.slice(0, 8) }));
  const deadline = Date.now() + 90_000;
  while (Date.now() < deadline) {
    const state = await call('/v1/state');
    const task = state.tasks?.find(value => value.id === receipt.taskId);
    if (!state.online || !task) throw new Error('test_task_unavailable');
    if (task.pending?.length) throw new Error('test_requires_user_input_check_console');
    if (!task.turnId) {
      const answer = typeof task.answer === 'string' ? task.answer : '';
      console.log(JSON.stringify({ stage: label, settled: true,
        expectedMatched: answer.includes(expected), characters: answer.length,
        answerHash: createHash('sha256').update(answer).digest('hex').slice(0, 16) }));
      return receipt.taskId;
    }
    await pause();
  }
  throw new Error('test_timeout_check_console_do_not_resubmit');
}
try {
  const first = await trial('A');
  await trial('B', first);
  await trial('C');
  console.log('Finished: A=new task, B=same task with a different prompt, C=another new task.');
} catch (error) {
  const message = String(error?.message || 'unknown');
  console.error('Diagnostic stopped: ' + (/^[A-Za-z0-9_]+$/.test(message) ? message : 'network_or_protocol_error'));
  process.exitCode = 1;
}
