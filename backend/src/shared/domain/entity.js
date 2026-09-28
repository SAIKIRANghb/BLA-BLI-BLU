import { randomUUID } from 'node:crypto';

/**
 * Entity (abstract) - a domain object with a stable identity.
 * Identity (id) survives state changes, unlike ValueObjects.
 */
export class Entity {
  /**
   * @param {string} [id] existing id (persistence hydration) or omit to mint one
   * @param {object} [props]
   * @param {Date|string} [props.createdAt]
   */
  constructor(id = randomUUID(), props = {}) {
    this.id = id;
    this.createdAt = props.createdAt ? new Date(props.createdAt) : new Date();
  }

  /** @param {Entity} other */
  equals(other) {
    return other instanceof Entity && other.id === this.id;
  }
}

/**
 * AggregateRoot (abstract) - cluster of entities with a consistency boundary.
 * Only aggregates may be loaded/saved by repositories, and they publish
 * domain events after mutating (Observer pattern).
 */
export class AggregateRoot extends Entity {
  constructor(id, props) {
    super(id, props);
    /** @type {Array<{name:string, payload:object, occurredAt:Date}>} */
    this.domainEvents = [];
  }

  /**
   * @param {string} name
   * @param {object} payload
   */
  record(name, payload = {}) {
    this.domainEvents.push({ name, payload, occurredAt: new Date() });
    return this;
  }

  /** Drains recorded events (called by the unit of work / event bus). */
  pullDomainEvents() {
    const events = this.domainEvents;
    this.domainEvents = [];
    return events;
  }
}
