/**
 * EventBus - Observer / Publish-Subscribe.
 *
 * Domain layers publish facts (`order.placed`), infrastructure listeners react
 * (notifications, analytics, ...). Adding a listener never changes the publisher.
 */
export class EventBus {
  constructor() {
    /** @type {Map<string, Array<(payload:object)=>void>>} */
    this.listeners = new Map();
  }

  /**
   * @param {string} eventName
   * @param {(payload:object)=>void} handler
   * @returns {() => void} unsubscribe
   */
  on(eventName, handler) {
    const list = this.listeners.get(eventName) ?? [];
    list.push(handler);
    this.listeners.set(eventName, list);
    return () => this.off(eventName, handler);
  }

  off(eventName, handler) {
    const list = this.listeners.get(eventName) ?? [];
    this.listeners.set(
      eventName,
      list.filter((h) => h !== handler),
    );
  }

  /**
   * @param {string} eventName
   * @param {object} payload
   */
  emit(eventName, payload) {
    const list = this.listeners.get(eventName) ?? [];
    const wildcards = this.listeners.get('*') ?? [];
    for (const handler of [...list, ...wildcards]) {
      try {
        handler(payload);
      } catch {
        /* listeners must never break the request pipeline */
      }
    }
  }

  /** Publishes aggregate domain events and clears them. */
  publishAll(aggregate) {
    for (const event of aggregate.pullDomainEvents()) {
      this.emit(event.name, event.payload);
    }
  }
}
