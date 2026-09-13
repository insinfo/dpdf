# Documentação

| Documento | Assunto |
|---|---|
| [COBERTURA.md](COBERTURA.md) | Estado da implementação cláusula por cláusula da ISO 32000-1:2008, mais o estado dos pacotes `jbig2` e `dgfx`. O que está pronto, o que está parcial, o que falta, e o que está deliberadamente fora do alcance |

Documentação de uso fica no [README](../README.md) da raiz. As convenções do repositório,
incluindo a regra sobre mensagens de commit, estão em [AGENTS.md](../AGENTS.md).

## Sobre o documento de cobertura

Ele existe para responder uma pergunta que um README de projeto normalmente responde mal:
*o que desta especificação eu posso realmente usar hoje?*

A regra que ele segue é que **presença de código não conta como implementação**. Uma
cláusula só aparece como pronta quando existe teste exercitando o comportamento. Essa regra
não é acadêmica: o levantamento inicial encontrou um módulo de 1811 linhas, aparentemente
completo, que não era exportado, não era referenciado por nada e falhava na primeira vez que
foi executado.

Pela mesma razão, os verificadores de PDF/A e PDF/UA mantêm uma lista `unverifiedRules` com
as regras que estão fora do alcance deles, em vez de deixá-las passar caladas. Um relatório
de conformidade que esconde o que não checou é pior que nenhum relatório.
