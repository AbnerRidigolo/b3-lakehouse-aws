# Histórico completo — evidências do lote 1995–2024

Execuções concluídas em 08/10/2026; evidências locais conferidas em 10/10/2026. Esta conferência usa registros salvos durante a execução, sem nova consulta à AWS.

Os 40 anos completos de 1986–2025 estão carregados na silver, além do incremental de 01/10/2026: **3.185.477 cotações e 29.917 taxas**. Isso não representa todo o ano de 2026.

O lote acrescentou 2.394.863 cotações e 22.590 taxas em 30 execuções Glue SUCCEEDED, com controles DynamoDB SUCCESS. Os snapshots formam uma cadeia contínua; cada append acrescentou exatamente a contagem do respectivo ano, preservando as cargas anteriores.

Foram segregadas 363 linhas deste lote, somando 374 com os lotes anteriores. Os registros rejeitados permanecem rastreáveis na bronze/quarentena. Lacunas do BCB continuam explícitas, sem preenchimento artificial. A repetição do histórico anual não foi testada; a idempotência validada anteriormente se refere ao incremental diário.

## Execuções

| Ano | Cotações | Taxas | Quarentena | DPU-segundos | Run ID |
| --- | ---: | ---: | ---: | ---: | --- |
| 1995 | 54990 | 744 | 0 | 240.0 | jr_96436cff5a3b99b1e8055871aa6ef60c25dd085bd87c4732ac4eae808a76adc9 |
| 1996 | 57225 | 756 | 0 | 271.0 | jr_aaac51348f980b9d20c30e712c82729a7c7e3f1155c01425a238020d007b2868 |
| 1997 | 56139 | 756 | 0 | 219.0 | jr_643c225c931139577a04f233212fdb4ed646d19ff4970939e8f88aaa7eb78fed |
| 1998 | 48851 | 747 | 0 | 233.0 | jr_a334b8657e1e05d5cb66e5905a61e981cf7d9e52b9f1391ca745d624523594ff |
| 1999 | 57505 | 750 | 0 | 275.0 | jr_ce4cd4bb8819e5e5ac10403d75b57c7e10159ca4378a58ab72ddd71c95762cdd |
| 2000 | 58303 | 750 | 1 | 254.0 | jr_bfcb0ee94a91812f5e78c693e3220a1306fd2214a2ffa8396169da6bcec5fe38 |
| 2001 | 50714 | 750 | 0 | 313.0 | jr_f007f570b7d3e35d1001168bcaf0cbe226c9f1626f9ab39eb1292c9ab132b7b8 |
| 2002 | 48619 | 759 | 0 | 247.0 | jr_be9f8c67f4ecbff6417608aef252f86f4f6b1f66d01790d58114a6b2c2e31eb5 |
| 2003 | 51336 | 759 | 0 | 291.0 | jr_e1eb1d3d2c258161bd6f28b086b53576c79e50211a0c226888923c7a79d75a83 |
| 2004 | 54469 | 756 | 0 | 290.0 | jr_bfa4aa0589b7ac069e997a912df8b661bcb62699b853cb57230148a498892849 |
| 2005 | 55882 | 753 | 351 | 431.0 | jr_9bb6d5119a8f17b8330e83cae529cbd7ba63629e07703336e2245fc752ea404b |
| 2006 | 58701 | 747 | 1 | 298.0 | jr_059c0a57856664cfab57db65349e903848783f441068f774e807a834ba6b20f2 |
| 2007 | 83214 | 750 | 0 | 372.0 | jr_a6d6c2663aa2c9241373046e70bfa3291859e13a4bb1e7c03fa98cd9217a17d5 |
| 2008 | 87533 | 762 | 0 | 281.0 | jr_9808572658f5ad5a0fe6badc64701bc98fc59a0758948d1f2e07d864b60c94b0 |
| 2009 | 81747 | 750 | 0 | 251.0 | jr_17037c708c6892bd2ee751bd1cc56adebfc67d140c5d4d15f743e546fb5ea43f |
| 2010 | 81715 | 753 | 0 | 254.0 | jr_481c4a81fad7516131545588ba0562f6d287190c312167970e063150ac9635ae |
| 2011 | 82193 | 753 | 1 | 349.0 | jr_0a0698e380fe47facb308fde21ab1fee93444012bc87bcf02dac4593121e7ac0 |
| 2012 | 78614 | 753 | 0 | 281.0 | jr_e7eb1fd3eebfdb0acaf70a6614107a028c9e6e00dba966e74998c485876eff58 |
| 2013 | 78960 | 759 | 0 | 368.0 | jr_a26b44a954087f026cae3a583a444864a0bfada8592d4c621ff45c214ca3da67 |
| 2014 | 78255 | 759 | 0 | 331.0 | jr_b9fcd455993dc98e023efa79d0240be73e73dd14d61ed50d1626f74792e3e868 |
| 2015 | 77184 | 750 | 0 | 254.0 | jr_23b1dde9e9ac18cc2526c57b6805f7f2c3e4ed6ae49f5c793a5d59e04abde653 |
| 2016 | 78450 | 753 | 0 | 283.0 | jr_b227a220b2a3d9ef3f9e714bce8e9c363de246f1a639098a118f4a8f273073d9 |
| 2017 | 81721 | 747 | 0 | 293.0 | jr_f7b6b22bb2503ecae73e97ae341426ee416cc110ed82dfeb9db73486c7259f05 |
| 2018 | 88400 | 750 | 0 | 473.0 | jr_49efeb9149c33ea9d403ee3b85f990bd77e4ede85eb3886739d3712c533683b6 |
| 2019 | 90099 | 759 | 0 | 322.0 | jr_b366f09e8b3754938a2f16b210a4a7a3f6cd5da9e5e24ba93ec74f4e59df99ee |
| 2020 | 122218 | 753 | 8 | 395.0 | jr_575eff35b4111067ae0e8fbd9461a60b5dc7ab922e66fc823f82b2d9ecd496c1 |
| 2021 | 195326 | 753 | 1 | 365.0 | jr_5af34f1b591423dda925065d6219084a025b91bf034adb752cd2083d6600b517 |
| 2022 | 183278 | 753 | 0 | 505.0 | jr_e80b2f79ac2d15920aad7735c6905a3ae199aa1932c46c1347a9f4dcd25012c4 |
| 2023 | 87483 | 747 | 0 | 372.0 | jr_2301c869c6e66d4f41be59d55bfb8c7519e6e855dd30b51a58137f8027134548 |
| 2024 | 85739 | 759 | 0 | 298.0 | jr_2c08e3537b62522dca5cc574a023467534bf57e9cc6c4fd0107c92c7694ca36b |

## Custos e limites

Computação estimada deste lote: **USD 1,14999**, calculada a partir dos DPU-segundos registrados e da tarifa usada na estimativa autorizada (USD 0,44/DPU-hora). Reserva autorizada: USD 5. Não é o faturamento total: faltam conciliação atualizada e custos dos demais serviços.

Cada execução usou dois workers G.1X, timeout de 10 minutos, sem repetição automática e com processamento sequencial. O teto do projeto permanece USD 10, incluindo USD 2 de reserva para atraso de faturamento e encerramento.

## Próximas entregas

Gold com dbt/Athena, execução em Fargate, orquestração ponta a ponta e observabilidade ainda pendentes. O agendamento permanece desativado conforme a última configuração verificada. A autenticação local precisa ser restabelecida ou substituída por acesso operacional temporário antes de novas verificações ao vivo.

Evidências brutas locais: `local/batch-1995-2024/*-status.json` e `*-verified.json`, ignoradas pelo Git. [Lotes anteriores](history-batch-evidence.md).
