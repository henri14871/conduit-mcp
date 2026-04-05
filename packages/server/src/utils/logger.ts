/**
 * Logger that writes to stderr only — console.log is forbidden
 * because the MCP server communicates over stdout via stdio transport.
 */
export const log = {
  info: (...args: unknown[]) => console.error("[conduit]", ...args),
  warn: (...args: unknown[]) => console.error("[conduit:warn]", ...args),
  error: (...args: unknown[]) => console.error("[conduit:error]", ...args),
  debug: (...args: unknown[]) => {
    if (process.env.CONDUIT_DEBUG) {
      console.error("[conduit:debug]", ...args);
    }
  },
};
