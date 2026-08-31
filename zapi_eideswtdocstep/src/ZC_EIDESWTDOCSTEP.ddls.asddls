@AbapCatalog.sqlViewName: 'ZCEIDESWTDOCSTP'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'API NAPAI - Pasos de documento de cambio'
@Search.searchable: true
@OData.publish: true
define root view entity ZC_EIDESWTDOCSTEP
  as select from ZI_EIDESWTDOCSTEP
{
  key SwitchNum,
  key StepKey,
      ChangeTimestamp,
      Activity,
      Status
}
