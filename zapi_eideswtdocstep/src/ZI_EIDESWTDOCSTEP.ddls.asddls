@AbapCatalog.sqlViewName: 'ZIEIDESWTDOCSTP'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'Pasos de documento de cambio (EIDESWTDOCSTEP)'
define view ZI_EIDESWTDOCSTEP
  as select from eideswtdocstep
{
  key switchnum     as SwitchNum,
  key stepkey       as StepKey,
      timestamp     as ChangeTimestamp,
      activity      as Activity,
      status        as Status
}
