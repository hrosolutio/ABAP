# Clasificación de conceptos (ZFA_FRAUD_CONC)

Sacada de los textos de `TE835T`. La carga la hace el report
`ZFA_R_CARGA_FRAUD_CONC`. **Pendiente de revisar con Aleix.**

| Tipo | Significado | Luz | Gas |
|---|---|---|---|
| `EN` | Energía activa | `EACTPS` (agrupada), `EACTP1`-`EACTP3` (punta/llano/valle = P1-P3), `EACTF1`-`EACTF6` (P1-P6) | — |
| `TV` | Término variable | — | `GTVARI` |
| `PO` | Potencia (solo para la línea de potencia mayor a importe 0) | `EPOTP1`-`EPOTP6` | — |
| `DE` | Descuento sobre energía / TV | `EDACTS`, `EDEMPC` | `GDTVAR`, `GDEMPV`, `GDEMPC` |
| `IE` | IEE (%), `BELZART_REL` = su mínimo | `EIEE`/`EIER`/`EIEX`/`EIED`/`EIEM` + región | — |
| `IM` | Mínimo comunitario, `BELZART_REL` = su IEE | `EMIC`/`EMIR`/`EMIX`/`EMID`/`EMIM` + región | — |
| `IH` | Impuesto de hidrocarburos | — | `GIEH`/`GIEX`/`GIED` + región |

Región: `AL` Álava, `GE` General, `GU` Guipúzcoa, `NA` Navarra, `VI` Vizcaya.

Conceptos fijos del DF (en el código, no en la tabla): `EREPOS` / `GREPOS`
(Reposición Factura) y `PGINTR` / `PGIRAP` (Intervención rápida).

## Fuera, a confirmar

- Autoconsumo: `EAIMP*`, `EEIMP*`, `EEXCP*`, `PEAUT*`. El DF no lo menciona.
- Descuentos que no son sobre energía/TV: `EDPOTS`, `EDEMPP`, `EDEMPA`,
  `EDCTPL`, `GDTFIJ`, `GDEMPF`, `GDEMPA`, `GDCTPL`.
- `GDEMPB` (Bonificación consumo gas) y `GDEMPI` (Bonificación IVA gas):
  ¿son descuentos sobre el TV?
- `EIEE` y `EMIC` sin región son "Informativo": no se usan.

## Ideas para validaciones de integridad

- **2.2 Exención de impuestos**: si el cálculo original lleva `EIEX*`,
  `EIED*`, `EMIX*`, `EMID*`, `GIEX*` o `GIED*`, el contrato está exento.
- **2.7 Tarifa Plana**: si el cálculo original lleva conceptos de Tarifa
  Plana (`ETP*`, `GTP*`, `GTPLAN`), el cliente tenía Tarifa Plana en ese
  periodo.
