// Retain the newest server value while a local edit is awaiting acknowledgement.
export class SettingsInbox {
  constructor(apply) {
    this.apply = apply;
    this.pending = false;
    this.latest = null;
    this.appliedRevision = -1;
  }
  receive(value) {
    if (!value || !Number.isSafeInteger(value.revision) || value.revision < 0) return;
    if (this.latest && value.revision < this.latest.revision) return;
    this.latest = { ...value };
    this.flush();
  }
  setPending(value) {
    this.pending = value;
    this.flush();
  }
  flush() {
    if (this.pending || !this.latest || this.latest.revision <= this.appliedRevision) return;
    this.appliedRevision = this.latest.revision;
    this.apply(this.latest);
  }
}
