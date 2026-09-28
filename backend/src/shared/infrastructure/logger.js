/**
 * Logger - Strategy pattern: formatting strategy is injected, the API never
 * changes. Quiet in tests, pretty in dev, structured JSON in production.
 */
class BaseStrategy {
  write(_level, _message, _meta) {}
  out(line) {
    // eslint-disable-next-line no-console
    console.log(line);
  }
}

class PrettyStrategy extends BaseStrategy {
  write(level, message, meta) {
    const colors = { info: '\x1b[36m', warn: '\x1b[33m', error: '\x1b[31m', debug: '\x1b[90m' };
    const c = colors[level] ?? '';
    const metaStr = meta && Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
    this.out(`${c}[${level.toUpperCase()}]\x1b[0m ${new Date().toISOString()} ${message}${metaStr}`);
  }
}

class JsonStrategy extends BaseStrategy {
  write(level, message, meta) {
    this.out(JSON.stringify({ level, message, time: new Date().toISOString(), ...meta }));
  }
}

class SilentStrategy extends BaseStrategy {
  write() {}
}

class Logger {
  /** @param {BaseStrategy} strategy */
  constructor(strategy = new PrettyStrategy()) {
    this.strategy = strategy;
  }

  /** @param {BaseStrategy} strategy */
  setStrategy(strategy) {
    this.strategy = strategy;
    return this;
  }

  info(message, meta) {
    this.strategy.write('info', message, meta);
  }

  warn(message, meta) {
    this.strategy.write('warn', message, meta);
  }

  error(message, meta) {
    this.strategy.write('error', message, meta);
  }

  debug(message, meta) {
    this.strategy.write('debug', message, meta);
  }
}

export function createLogger(mode = 'development') {
  if (mode === 'production') return new Logger(new JsonStrategy());
  if (mode === 'test') return new Logger(new SilentStrategy());
  return new Logger(new PrettyStrategy());
}

export { Logger, PrettyStrategy, JsonStrategy, SilentStrategy };
