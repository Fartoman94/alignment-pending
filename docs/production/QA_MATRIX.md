# QA matrix

## Critical flows
| Flow | Checks |
|---|---|
| New campaign | seed, difficulty, company name, initial office |
| Build | preview, rotation, collision, cost, refund, pathing |
| Staff | hire, assign, pay, fire, resign, save/load |
| Train | configure, start, pause game, finish, cancel, insufficient compute |
| Evaluate | uncertainty, repeat eval, cost, warning persistence |
| Deploy | internal/beta/public, staged rollout, rate limit, rollback |
| Incident | trigger, pause, choice, delayed effect, history |
| Finance | ledger, runway, funding, bankruptcy recovery |
| Save | manual, autosave rotation, corrupt newest, migration |
| Settings | resolution, audio, UI scale, remapping, reduced motion |
| Endings | each family reachable, epilogue variables correct |

## Resolution test set
1280x720, 1600x900, 1920x1080, 2560x1440, ultrawide sanity check.

## Soak tests
- 2 simulated in-game years at 4x headless where possible.
- 150 staff stress scene for 20 minutes.
- Repeated save/load 100 cycles in test fixture.
