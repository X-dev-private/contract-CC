# FeeVault: contrato do Zueirinha (Cara ou Coroa)

Contrato em Solidity que recebe ETH, fica com uma pequena taxa e guarda o restante para a pessoa sacar depois. Ele foi feito para o **[Zueirinha: Cara ou Coroa](../zueirinha)**, o jogo de cara ou coroa que fica na pasta ao lado deste projeto.

## Endereço do contrato

| Rede    | Endereço                                     |
| ------- | -------------------------------------------- |
| Sepolia | `0xEca4543ef3933746faBb4e4E9f0b221b9CEBf0a4` |

Ver no Etherscan: https://sepolia.etherscan.io/address/0xEca4543ef3933746faBb4e4E9f0b221b9CEBf0a4#code

O código está verificado no Etherscan, no Sourcify e no Blockscout. Isso quer dizer que qualquer pessoa pode ler o código-fonte publicado e conferir que ele é o mesmo que está rodando na rede.

- **Dono:** `0x76FD1f5839572eeDc0bab748E98301f3Ae18a91F`
- **Taxa:** 1% (100 basis points)

A Sepolia é uma rede de testes, então o ETH usado lá não tem valor real.

A primeira versão, só com depósito e saque, ficou em `0x9b383a8B0C8F9C660A943b06EF8705d1Ad792fc0`. Ela não tem as apostas e não deve mais ser usada.

## Onde ele é usado: o jogo de cara ou coroa

O Zueirinha é um site em React onde duas pessoas escolhem quem é Cara e quem é Coroa, dizem o que está sendo apostado e jogam a moeda. O contrato guarda o ETH dos jogadores e faz a aposta de verdade na blockchain:

1. **Depositar:** cada pessoa conecta a carteira (MetaMask ou outra compatível) e chama `deposit()` enviando ETH. O contrato fica com 1% de taxa e credita os outros 99% no saldo da pessoa (`balanceOf`).
2. **Criar a aposta:** uma pessoa chama `createBet(valor, lado)`, com lado 0 = Cara e 1 = Coroa. O valor sai do saldo dela e fica travado na aposta.
3. **Entrar na aposta:** a outra pessoa chama `joinBet(id)`, entra com o mesmo valor e fica com o lado oposto.
4. **Jogar a moeda:** a partir do bloco seguinte, qualquer pessoa chama `resolveBet(id)`. O contrato sorteia o lado e o vencedor recebe o dobro do valor no saldo.
5. **Devolver (opcional):** se a partida foi só pelo esporte, o vencedor pode chamar `returnToLoser(id, valor)` e devolver ao perdedor o que ele apostou, inteiro ou só uma parte.
6. **Sacar:** cada pessoa saca o próprio saldo com `withdraw(valor)`, e o dono do contrato saca as taxas com `withdrawFees(destino)`.

Antes de alguém entrar, quem criou a aposta pode desistir com `cancelBet(id)`, e o valor volta para o saldo.

### Como o sorteio funciona

O resultado vem do hash do bloco seguinte ao `joinBet`. Quando a segunda pessoa entra na aposta, esse bloco ainda não existe, então ninguém consegue prever o resultado ou desistir ao ver que perderia.

O EVM só guarda o hash dos últimos 256 blocos. Se ninguém chamar `resolveBet` nesse prazo (uns 50 minutos), a aposta não é sorteada e o valor volta para os dois.

Esse sorteio é bom o bastante para a rede de testes. Com dinheiro de verdade, quem valida os blocos teria alguma influência sobre o hash, e o certo seria usar um serviço de sorteio externo, como o [Chainlink VRF](https://docs.chain.link/vrf).

### O que já está pronto no jogo

Hoje o jogo **só conecta a carteira**. Isso está em [`zueirinha/src/component/carteira.ts`](../zueirinha/src/component/carteira.ts), usando web3.js, e no botão [`BotaoCarteira.tsx`](../zueirinha/src/component/BotaoCarteira.tsx). O jogo ainda não chama o contrato: o sorteio que aparece na tela continua acontecendo no navegador, em [`jogo.ts`](../zueirinha/src/component/jogo.ts).

### Como ligar o jogo ao contrato

Exemplo com web3.js, a mesma biblioteca que o jogo já usa. A carteira precisa estar na rede Sepolia.

```ts
import { Web3 } from 'web3'

const ENDERECO = '0xEca4543ef3933746faBb4e4E9f0b221b9CEBf0a4'
const ABI = [
  { type: 'function', name: 'deposit', stateMutability: 'payable', inputs: [], outputs: [] },
  { type: 'function', name: 'withdraw', stateMutability: 'nonpayable', inputs: [{ name: 'amount', type: 'uint256' }], outputs: [] },
  { type: 'function', name: 'balanceOf', stateMutability: 'view', inputs: [{ name: '', type: 'address' }], outputs: [{ type: 'uint256' }] },
] as const

const web3 = new Web3(window.ethereum)
const contrato = new web3.eth.Contract(ABI, ENDERECO)

// Depositar 0.01 ETH (0.0001 fica de taxa)
await contrato.methods.deposit().send({ from: conta, value: web3.utils.toWei('0.01', 'ether') })

// Ver o saldo da pessoa no contrato
const saldo = await contrato.methods.balanceOf(conta).call()

// Sacar tudo
await contrato.methods.withdraw(saldo).send({ from: conta })
```

O ABI completo fica em `artifacts/contracts/FeeVault.sol/FeeVault.json` depois de rodar `npx hardhat build`.

## Como o contrato funciona

O código está em [`contracts/FeeVault.sol`](contracts/FeeVault.sol).

| Função                      | Quem pode chamar | O que faz                                                    |
| --------------------------- | ---------------- | ------------------------------------------------------------ |
| `deposit()`                 | Qualquer pessoa  | Recebe ETH, separa a taxa e credita o resto para quem enviou |
| Enviar ETH direto           | Qualquer pessoa  | Funciona igual ao `deposit()`                                |
| `withdraw(amount)`          | Qualquer pessoa  | Saca do próprio saldo                                        |
| `balanceOf(endereco)`       | Qualquer pessoa  | Mostra o saldo de um endereço                                |
| `collectedFees()`           | Qualquer pessoa  | Mostra quanto de taxa já foi acumulado                       |
| `withdrawFees(destino)`     | Só o dono        | Envia as taxas acumuladas para `destino`                     |
| `createBet(valor, lado)`    | Qualquer pessoa  | Cria uma aposta com o próprio saldo (0 = Cara, 1 = Coroa)    |
| `joinBet(id)`               | Outra pessoa     | Entra na aposta com o mesmo valor, no lado oposto            |
| `resolveBet(id)`            | Qualquer pessoa  | Sorteia o lado e paga o dobro ao vencedor                    |
| `cancelBet(id)`             | Quem criou       | Cancela a aposta enquanto ninguém entrou                     |
| `returnToLoser(id, valor)`  | Só o vencedor    | Devolve ao perdedor parte ou todo o valor que ele apostou    |
| `bets(id)`                  | Qualquer pessoa  | Mostra os dados de uma aposta                                |
| `setFeeBps(novaTaxa)`       | Só o dono        | Muda a taxa (máximo de 500, ou seja, 5%)                     |
| `transferOwnership(novo)`   | Só o dono        | Passa o contrato para outro dono                             |

A taxa é medida em basis points: 100 = 1%. Exemplo com 1%: num depósito de 1 ETH, 0,99 ETH vai para o saldo da pessoa e 0,01 ETH fica de taxa.

As apostas não cobram taxa nova, porque o 1% já foi cobrado no depósito.

O saque tem proteção contra reentrância, um ataque em que outro contrato tenta sacar várias vezes antes de o saldo ser atualizado.

## Como rodar

Você precisa do [Node.js](https://nodejs.org).

```bash
npm install
```

### Testes

```bash
npx hardhat test solidity
```

Os testes ficam em [`contracts/FeeVault.t.sol`](contracts/FeeVault.t.sol).

### Deploy

1. Copie o `.env.example` para `.env` e coloque a chave privada da carteira que vai pagar o deploy:
   ```
   SEPOLIA_PRIVATE_KEY=0x...
   ```
   O `.env` está no `.gitignore` e não deve ser compartilhado. Quem tem essa chave controla a carteira.
2. Rode o deploy:
   ```bash
   npx hardhat ignition deploy ignition/modules/FeeVault.ts --network sepolia --deployment-id sepolia-v2
   ```
   Depois de mudar o código do contrato, use um `--deployment-id` novo (por exemplo `sepolia-v3`) para publicar como um contrato novo.

A taxa inicial é 1%. Para começar com outra taxa, passe o parâmetro `feeBps` para o módulo do Ignition.

A conexão com a Sepolia usa a RPC pública `https://ethereum-sepolia-rpc.publicnode.com`, configurada no [`hardhat.config.ts`](hardhat.config.ts).

## Estrutura do projeto

```
contracts/
├── FeeVault.sol          # O contrato
└── FeeVault.t.sol        # Testes em Solidity
ignition/modules/
└── FeeVault.ts           # Módulo de deploy
hardhat.config.ts         # Configuração do Hardhat (redes, compilador)
.env.example              # Modelo do .env
```

O projeto também traz os arquivos de exemplo do Hardhat (`Counter.sol`, `test/Counter.ts`, `scripts/send-op-tx.ts`), que não são usados pelo jogo.
