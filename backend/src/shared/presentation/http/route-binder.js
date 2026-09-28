import express from 'express';
import { asyncHandler } from './http.js';
import { validate } from './middlewares.js';

/**
 * bindRoutes - generic Router table -> express wiring (Template Method).
 *
 * Every entry of a module's route table gets, automatically:
 *   1. schema validation (params/query/body via Zod)
 *   2. its own middlewares (e.g. requireAuth decorators)
 *   3. async error forwarding to the terminal error middleware
 *
 * Route entry: { method, path, schemas?, middleware?, handler }
 *
 * @param {import('./http.js').Router} table
 * @returns {import('express').Router}
 */
export function bindRoutes(table) {
  const router = express.Router();
  for (const entry of table.routes) {
    const validations = entry.schemas ? [validate(entry.schemas)] : [];
    const chain = [...validations, ...(entry.middleware ?? []), asyncHandler(entry.handler)];
    router[entry.method](entry.path, ...chain);
  }
  return router;
}
