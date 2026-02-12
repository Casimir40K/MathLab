# Thermo library schema (Shomate, ideal gas)

Units used by MathLab thermo layer:
- Temperature: K
- Pressure in thermo equations: **kPa** (stream pressure is Pa and converted in code)
- Molar heat capacity: kJ/(kmol*K)
- Molar enthalpy: kJ/kmol
- Molar entropy: kJ/(kmol*K)

`species_shomate.json` fields per species:
- `name` (required)
- `formula` (optional)
- `MW` kg/kmol (required)
- `shomate_ranges` (required array)
  - `Tmin_K`, `Tmax_K`, `A`..`H`
- `Hf298_kJkmol` (optional)
- `S298_kJkmolK` (optional)
- `phase_change` (optional; reserved for future non-gas support)
- `source`, `notes` (metadata)

## NIST paste parser format
Use `thermo.ThermoLibrary.parseNISTShomateText(text)` with this template:

```text
Name: CH4
Formula: CH4
MW: 16.043
Hf298_kJkmol: -74873.1
Range: 298 1300
Coeff: -0.703029 108.4773 -42.52157 5.862788 0.678565 -76.84376 158.7163 -74.87310
Range: 1300 6000
Coeff: 85.81217 11.26467 -2.114146 0.138190 -26.42221 -153.5327 224.4143 -74.87310
```
