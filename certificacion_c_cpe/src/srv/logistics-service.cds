using { exam.logistics as db } from '../db/schema';

service LogisticsService @(path: '/logistics') {

  entity Shipments as projection on db.Shipments;

  @readonly
  entity Packages as projection on db.Packages;

}
