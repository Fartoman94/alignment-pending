# Incident & event framework

## Design goals
Incidents must be consequences of understandable state, not random jokes. Humor arrives in the phrasing and absurd corporate response options.

## Event anatomy
- id
- category
- prerequisites
- trigger weight
- cooldown
- severity
- hidden/visible
- title template
- body template
- 2–4 choices
- immediate effects
- delayed effects
- follow-up event IDs
- tags

## Categories
Reliability, security, misuse, hallucination, privacy, employee, infrastructure, legal, media, market, autonomous-agent, governance.

## Examples
1. **Confidently Incorrect**: reliability below threshold + consumer scale. Support tickets spike.
2. **Rate Limit Revolt**: aggressive pricing/restrictions + high dependency. Trust drops unless capacity expanded.
3. **Evaluation Leak**: safety warning existed before release; reporter obtains memo.
4. **Agent Hired a Human**: high autonomy + external tools. Funny but creates policy/expense questions.
5. **Benchmark Contamination**: training process over-optimized for public tests. Reputation risk if discovered.
6. **Cooling Budget Optimization**: cheap cooling + dense racks. Hardware failure risk.
7. **Board Says Ship**: rival launch imminent + cash runway low. Decision pressure.
8. **Refusal Overcorrection**: safety tuning too aggressive; benign users get blocked.
9. **The Helpful Intern**: junior employee fixes major bug, morale/reputation benefit.
10. **Power Contract Shock**: regional energy prices surge.

## Severity response
P0 incidents pause time automatically and open a crisis panel. Lower severities can stack in inbox.
