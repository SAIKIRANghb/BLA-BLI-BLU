import { Entity } from '../../../shared/domain/entity.js';
import { Slug } from '../../../shared/domain/identifiers.js';

/**
 * Faq - content entity (question/answer pair, ordered within a category).
 */
export class Faq extends Entity {
  constructor({ id, category = 'General', question, answer, position = 0, createdAt }) {
    super(id, { createdAt });
    this.category = category;
    this.question = question;
    this.answer = answer;
    this.position = position;
  }

  toDto() {
    return {
      id: this.id,
      category: this.category,
      question: this.question,
      answer: this.answer,
      position: this.position,
    };
  }
}

/**
 * CmsPage - static/legal content (about, refund policy, ...).
 */
export class CmsPage extends Entity {
  constructor({ id, handle, title, body, createdAt }) {
    super(id, { createdAt });
    this.handle = handle instanceof Slug ? handle : new Slug(handle);
    this.title = title;
    this.body = body;
  }

  toDto() {
    return { handle: this.handle.value, title: this.title, body: this.body };
  }
}

/**
 * SiteConfig - key/value aggregate holding home page composition and chrome
 * (footer, social links, banners). Returned mostly as-is: the payload is data,
 * not behaviour, so presentation can render it verbatim.
 */
export class SiteConfig extends Entity {
  constructor({ id, key, payload, createdAt }) {
    super(id, { createdAt });
    this.key = key;
    this.payload = payload ?? {};
  }

  toDto() {
    return this.payload;
  }
}
