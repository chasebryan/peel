# PEEL repository rules

These rules are binding for all future work in this repository.

1. PEEL remains minimal.
2. Proof obligations may never be bypassed to make a gate pass.
3. Every semantic change requires an updated interface, a positive test, a negative test when rejection behavior changes, an update to `docs/SEMANTICS.md`, and an update to `docs/TRUST.md` if the trusted computing base changes.
4. Every toolchain upgrade requires immutable new pins, compatibility evidence, a complete `make check`, and an explicit changelog entry in the relevant future commit or pull request.
5. Do not add a parser, package manager, optimizer, general AST, HACL*/EverCrypt integration, protocol implementation, or additional backend until P0 passes and the owner explicitly authorizes the next phase.
6. Do not claim constant-time behavior from generated C without a separately defined and executed side-channel validation gate.
7. Generated artifacts never belong in Git.
8. Never state that tests passed without recording the commands actually executed.
9. Preserve unrelated user changes.
10. Do not commit, push, release, or open a pull request unless the user explicitly requests it.
