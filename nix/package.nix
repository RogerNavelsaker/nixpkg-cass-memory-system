{ bash, bun, bun2nix, lib, makeWrapper, symlinkJoin }:

let
  manifest = builtins.fromJSON (builtins.readFile ./package-manifest.json);
  baseProgram = manifest.binary.baseProgram or manifest.binary.name;
  sourceRoot = builtins.path {
    path = ../upstream;
    name = "source";
  };
  licenseMap = {
    "MIT" = lib.licenses.mit;
    "Apache-2.0" = lib.licenses.asl20;
  };
  resolvedLicense =
    if builtins.hasAttr manifest.meta.licenseSpdx licenseMap
    then licenseMap.${manifest.meta.licenseSpdx}
    else lib.licenses.unfree;
  aliasScripts = lib.concatMapStrings
    (
      alias:
      ''
        cat > "$out/bin/${alias}" <<EOF
#!${lib.getExe bash}
exec "$out/bin/${manifest.binary.name}" "\$@"
EOF
        chmod +x "$out/bin/${alias}"
      ''
    )
    (manifest.binary.aliases or [ ]);
  basePackage = bun2nix.writeBunApplication {
    pname = manifest.package.repo;
    version = manifest.package.version;
    packageJson = ../upstream/package.json;
    src = sourceRoot;
    dontUseBunBuild = true;
    dontUseBunCheck = true;
    startScript = ''
      bun ${manifest.binary.entrypoint} "$@"
    '';
    bunDeps = bun2nix.fetchBunDeps {
      bunNix = ../bun.nix;
    };
    meta = with lib; {
      description = manifest.meta.description;
      homepage = manifest.meta.homepage;
      license = resolvedLicense;
      mainProgram = manifest.binary.name;
      platforms = platforms.linux ++ platforms.darwin;
      broken = !(builtins.pathExists ../bun.nix);
    };
  };
in
symlinkJoin {
  pname = manifest.binary.name;
  version = manifest.package.version;
  name = "${manifest.binary.name}-${manifest.package.version}";
  outputs = [ "out" ];
  paths = [ basePackage ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm -rf "$out/bin"
    mkdir -p "$out/bin"
    cat > "$out/bin/${manifest.binary.name}" <<EOF
#!${lib.getExe bash}
exec "${basePackage}/bin/${baseProgram}" "\$@"
EOF
    chmod +x "$out/bin/${manifest.binary.name}"
    ${aliasScripts}
  '';
  meta = basePackage.meta;
}
