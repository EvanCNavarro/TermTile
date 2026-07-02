# Command Portability

This project is macOS-first.

BSD and GNU command behavior can differ. Prefer project scripts, Node utilities, or documented guards when behavior must be portable. Use gtimeout only when coreutils is installed; otherwise prefer a Node-based timeout wrapper.
