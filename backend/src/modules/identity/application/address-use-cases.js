import { UseCase } from '../../../shared/application/use-case.js';
import { DomainError } from '../../../shared/domain/domain-error.js';
import { Address } from '../domain/index.js';

/** ListAddresses - saved addresses of the current customer. */
export class ListAddresses extends UseCase {
  constructor({ addressRepo }) {
    super();
    this.addressRepo = addressRepo;
  }

  async execute({ actor }) {
    const items = await this.addressRepo.listByUser(actor.id);
    return items.map((a) => a.toDto());
  }
}

/** SaveAddress - create or update a validated address (first one becomes default). */
export class SaveAddress extends UseCase {
  constructor({ addressRepo }) {
    super();
    this.addressRepo = addressRepo;
  }

  async execute({ actor, id, ...fields }) {
    const existing = id ? await this.addressRepo.findById(id) : null;
    if (existing && existing.userId !== actor.id) throw DomainError.forbidden('Not your address');

    const existingList = await this.addressRepo.listByUser(actor.id);
    const address = new Address({
      id: existing?.id,
      userId: actor.id,
      label: fields.label ?? existing?.label ?? 'Home',
      line1: fields.line1 ?? existing?.line1,
      line2: fields.line2 ?? existing?.line2,
      city: fields.city ?? existing?.city,
      state: fields.state ?? existing?.state,
      pincode: fields.pincode ?? existing?.pincode,
      phone: fields.phone ?? existing?.phone,
      isDefault: fields.isDefault ?? (existingList.length === 0 ? true : existing?.isDefault ?? false),
      createdAt: existing?.createdAt,
    });
    await this.addressRepo.save(address);
    return address.toDto();
  }
}

/** DeleteAddress */
export class DeleteAddress extends UseCase {
  constructor({ addressRepo }) {
    super();
    this.addressRepo = addressRepo;
  }

  async execute({ actor, id }) {
    await this.addressRepo.delete(id, actor.id);
    return { id, deleted: true };
  }
}
