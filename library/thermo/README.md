# MathLab Thermodynamic Data Library

## Species Data: `species_shomate.json`

Contains ideal-gas Shomate equation coefficients for thermodynamic property
evaluation (cp, h, s) as a function of temperature.

### Units

| Property        | Unit           | Notes                                  |
|-----------------|----------------|----------------------------------------|
| Temperature     | K              | Shomate uses t = T/1000               |
| cp              | kJ/(kmol·K)    | Numerically = J/(mol·K)               |
| Enthalpy        | kJ/kmol        | Sensible: H(T) - H(298.15 K)         |
| Entropy         | kJ/(kmol·K)    | Standard state at P0 = 1 bar          |
| MW              | kg/kmol        |                                        |
| Hf298_kJkmol    | kJ/kmol        | Standard enthalpy of formation         |
| Pressure ref    | 1 bar = 1e5 Pa |                                        |

### Shomate Equations (NIST Convention)

```
t = T[K] / 1000

cp [J/(mol·K)] = A + B·t + C·t² + D·t³ + E/t²

H(T)-H(298.15) [kJ/mol] = A·t + B·t²/2 + C·t³/3 + D·t⁴/4 - E/t + F - H

S [J/(mol·K)] = A·ln(t) + B·t + C·t²/2 + D·t³/3 - E/(2·t²) + G
```

### Schema Per Species

**Required:**
- `name` — species identifier (e.g., "N2")
- `MW` — molecular weight [kg/kmol]
- `shomate_ranges` — array of objects, each with:
  - `Tmin`, `Tmax` — validity range [K]
  - `A`, `B`, `C`, `D`, `E`, `F`, `G`, `H` — Shomate coefficients

**Optional:**
- `formula` — chemical formula
- `Hf298_kJkmol` — standard enthalpy of formation at 298.15 K [kJ/kmol]
- `S298_kJkmolK` — standard entropy at 298.15 K [kJ/(kmol·K)]
- `phase_change` — future use: `Tb_K`, `Hvap_kJkmol`, `Antoine` coefficients
- `source`, `notes` — metadata strings

### Adding Species

Use the paste-parser helper:

```matlab
txt = fileread('nist_paste.txt');   % tab/space-separated NIST table
sp = thermo.addSpeciesFromNISTShomateText('NH3', 17.031, txt, ...
    'Hf298_kJkmol', -45940);
lib = thermo.ThermoLibrary();
lib.addSpecies(sp);
lib.saveJSON('library/thermo/species_shomate.json');
```

### Starter Species Included

N2, O2, H2, H2O (gas), CO2, CO, CH4, Ar
