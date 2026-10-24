import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../core/excecoes.dart';

/// Acesso à posição do dispositivo, isolando a dependência do pacote
/// `geolocator` do restante do aplicativo.
///
/// Concentrar aqui a verificação de serviço e de permissão evita repetir esse
/// tratamento em cada tela e permite que as telas apenas tratem
/// [FalhaLocalizacao], que já traz uma mensagem pronta para o usuário.
class LocalizacaoService {
  const LocalizacaoService();

  /// Confere se o GPS está ligado e se a permissão foi concedida.
  ///
  /// Lança [FalhaLocalizacao] com orientação específica quando o serviço está
  /// desligado, a permissão foi negada ou foi negada definitivamente.
  Future<void> garantirPermissao() async {
    final servicoLigado = await Geolocator.isLocationServiceEnabled();
    if (!servicoLigado) {
      throw const FalhaLocalizacao(
        'O serviço de localização do aparelho está desligado. '
        'Ative o GPS para usar a navegação.',
      );
    }

    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }

    if (permissao == LocationPermission.denied) {
      throw const FalhaLocalizacao(
        'A permissão de localização foi negada. '
        'Autorize o acesso à localização para acompanhar a rota.',
      );
    }
    if (permissao == LocationPermission.deniedForever) {
      throw const FalhaLocalizacao(
        'A permissão de localização está bloqueada definitivamente. '
        'Libere o acesso nas configurações do aparelho.',
      );
    }
  }

  /// Posição atual do dispositivo, obtida uma única vez.
  Future<Position> posicaoAtual() async {
    await garantirPermissao();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } on LocationServiceDisabledException {
      throw const FalhaLocalizacao(
        'O serviço de localização foi desligado durante a navegação.',
      );
    } on TimeoutException {
      throw const FalhaLocalizacao(
        'Não foi possível obter a sua posição a tempo. '
        'Vá para um local aberto e tente novamente.',
      );
    }
  }

  /// Fluxo contínuo de posições, usado durante a navegação assistida.
  ///
  /// [distanciaMinimaMetros] evita notificações a cada pequena variação do
  /// GPS, economizando bateria e reduzindo oscilações no mapa.
  Stream<Position> acompanhar({double distanciaMinimaMetros = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanciaMinimaMetros.round(),
      ),
    );
  }
}
