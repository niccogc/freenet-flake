{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation rec {
  pname = "freenet-core";
  version = "0.1.135"; # freenet-version
  src = fetchurl {
    url = "https://github.com/freenet/freenet-core/releases/download/v${version}/freenet-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-TUp3Ljwm41WPUKj6zNVKZH+jJawrp/f+BS49wRx9DNw=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  unpackPhase = "tar -xzf $src";

  installPhase = ''
    mkdir -p $out/bin
    cp freenet $out/bin/
    chmod +x $out/bin/freenet
  '';

  meta = with lib; {
    description = "Freenet Core - A decentralized, censorship-resistant network";
    homepage = "https://github.com/freenet/freenet-core";
    license = licenses.mit;
    platforms = ["x86_64-linux"];
    mainProgram = "freenet";
  };
}
