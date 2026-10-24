/// Exceções de domínio do aplicativo.
///
/// A camada de telas nunca mostra o texto cru de um erro de rede ou de banco
/// ao usuário: os serviços traduzem a falha para uma destas exceções, que já
/// carregam uma mensagem em português adequada para exibição.
library;

/// Classe base para falhas que podem ser apresentadas ao usuário.
abstract class FalhaApp implements Exception {
  const FalhaApp(this.mensagem, {this.detalheTecnico});

  /// Mensagem pronta para exibição na interface.
  final String mensagem;

  /// Informação adicional para registro em log, nunca exibida diretamente.
  final String? detalheTecnico;

  @override
  String toString() =>
      '$runtimeType: $mensagem${detalheTecnico == null ? '' : ' ($detalheTecnico)'}';
}

/// Falha ao converter um endereço em coordenadas.
class FalhaGeocodificacao extends FalhaApp {
  const FalhaGeocodificacao(super.mensagem, {super.detalheTecnico});
}

/// O endereço informado não foi localizado pelo serviço de geocodificação.
class EnderecoNaoEncontrado extends FalhaApp {
  const EnderecoNaoEncontrado([String? endereco])
      : super(
          endereco == null
              ? 'Endereço não encontrado. Verifique os dados informados.'
              : 'Não foi possível localizar o endereço "$endereco". '
                  'Confira o texto ou acrescente a cidade e o estado.',
        );
}

/// Falha ao calcular o trajeto entre os pontos.
class FalhaRoteamento extends FalhaApp {
  const FalhaRoteamento(super.mensagem, {super.detalheTecnico});
}

/// Falha relacionada a login, cadastro ou sessão.
class FalhaAutenticacao extends FalhaApp {
  const FalhaAutenticacao(super.mensagem, {super.detalheTecnico});
}

/// Operação recusada por falta de dados obrigatórios ou inconsistentes.
class DadosInvalidos extends FalhaApp {
  const DadosInvalidos(super.mensagem, {super.detalheTecnico});
}

/// Falha ao acessar o serviço de localização do dispositivo.
class FalhaLocalizacao extends FalhaApp {
  const FalhaLocalizacao(super.mensagem, {super.detalheTecnico});
}
