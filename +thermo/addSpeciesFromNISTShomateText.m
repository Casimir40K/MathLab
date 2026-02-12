function lib = addSpeciesFromNISTShomateText(textBlob, libraryPath)
%ADDSPECIESFROMNISTSHOMATETEXT Parse pasted NIST Shomate blocks and save.
% See library/thermo/README.md for expected paste format.

if nargin < 2 || isempty(libraryPath)
    libraryPath = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'library', 'thermo', 'species_shomate.json');
end
lib = thermo.ThermoLibrary(libraryPath);
lib.addSpeciesFromNISTShomateText(textBlob);
lib.save(libraryPath);
end
