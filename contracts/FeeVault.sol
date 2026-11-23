// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title FeeVault
/// @notice Usuários depositam ETH; o contrato retém uma pequena taxa
///         (em basis points) e o restante fica disponível para saque.
contract FeeVault {
    /// @dev 10_000 bps = 100%
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @dev Taxa máxima permitida: 5%
    uint256 public constant MAX_FEE_BPS = 500;

    address public owner;
    uint256 public feeBps;
    uint256 public collectedFees;

    mapping(address => uint256) public balanceOf;

    bool private locked;

    event Deposited(address indexed user, uint256 amount, uint256 fee, uint256 credited);
    event Withdrawn(address indexed user, uint256 amount);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error ZeroAmount();
    error ZeroAddress();
    error FeeTooHigh();
    error InsufficientBalance();
    error TransferFailed();
    error Reentrancy();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (locked) revert Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    /// @param _feeBps taxa inicial em basis points (ex.: 100 = 1%)
    constructor(uint256 _feeBps) {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        owner = msg.sender;
        feeBps = _feeBps;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Deposita ETH. A taxa fica no contrato e o resto é creditado ao usuário.
    function deposit() public payable {
        if (msg.value == 0) revert ZeroAmount();

        uint256 fee = (msg.value * feeBps) / BPS_DENOMINATOR;
        uint256 credited = msg.value - fee;

        collectedFees += fee;
        balanceOf[msg.sender] += credited;

        emit Deposited(msg.sender, msg.value, fee, credited);
    }

    /// @notice Enviar ETH diretamente ao contrato também conta como depósito.
    receive() external payable {
        deposit();
    }

    /// @notice Saca `amount` do saldo do usuário.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Dono saca as taxas acumuladas.
    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = collectedFees;
        if (amount == 0) revert ZeroAmount();

        collectedFees = 0;

        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit FeesWithdrawn(to, amount);
    }

    // ------------------------------------------------------------------
    // Cara ou coroa com o saldo do contrato
    // ------------------------------------------------------------------

    /// @dev Prazo para resolver uma aposta: o EVM só guarda os últimos 256 blockhashes
    uint256 public constant RESOLVE_WINDOW = 256;

    enum Side { Cara, Coroa }
    enum BetStatus { None, Open, Joined, Resolved, Cancelled, Refunded }

    struct Bet {
        address creator;
        address opponent;
        uint256 amount;
        Side creatorSide;
        BetStatus status;
        uint256 resolveBlock;
        address winner;
        uint256 returned; // quanto o vencedor já devolveu ao perdedor
    }

    uint256 public nextBetId;
    mapping(uint256 => Bet) public bets;

    event BetCreated(uint256 indexed betId, address indexed creator, uint256 amount, Side side);
    event BetJoined(uint256 indexed betId, address indexed opponent, uint256 resolveBlock);
    event BetResolved(uint256 indexed betId, Side result, address indexed winner, uint256 prize);
    event BetCancelled(uint256 indexed betId);
    event BetRefunded(uint256 indexed betId);
    event ReturnedToLoser(uint256 indexed betId, address indexed winner, address indexed loser, uint256 amount);

    error BetNotOpen();
    error BetNotJoined();
    error NotBetCreator();
    error CannotJoinOwnBet();
    error TooEarly();
    error NotBetWinner();
    error BetNotResolved();
    error ReturnTooHigh();

    /// @notice Cria uma aposta usando `amount` do saldo que você tem no contrato.
    /// @param side lado escolhido por quem cria (0 = Cara, 1 = Coroa)
    function createBet(uint256 amount, Side side) external returns (uint256 betId) {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;

        betId = nextBetId++;
        bets[betId] = Bet({
            creator: msg.sender,
            opponent: address(0),
            amount: amount,
            creatorSide: side,
            status: BetStatus.Open,
            resolveBlock: 0,
            winner: address(0),
            returned: 0
        });

        emit BetCreated(betId, msg.sender, amount, side);
    }

    /// @notice Entra numa aposta aberta com o mesmo valor, ficando com o outro lado.
    /// @dev O resultado usa o hash de um bloco futuro, para que ninguém
    ///      consiga saber o resultado (ou desistir ao ver que perderia) na hora de entrar.
    function joinBet(uint256 betId) external {
        Bet storage bet = bets[betId];
        if (bet.status != BetStatus.Open) revert BetNotOpen();
        if (msg.sender == bet.creator) revert CannotJoinOwnBet();
        if (balanceOf[msg.sender] < bet.amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= bet.amount;
        bet.opponent = msg.sender;
        bet.status = BetStatus.Joined;
        bet.resolveBlock = block.number + 1;

        emit BetJoined(betId, msg.sender, bet.resolveBlock);
    }

    /// @notice Joga a moeda e paga o vencedor. Qualquer pessoa pode chamar
    ///         depois que o bloco de resolução for minerado.
    ///         Se passar do prazo de 256 blocos, devolve o valor aos dois.
    function resolveBet(uint256 betId) external {
        Bet storage bet = bets[betId];
        if (bet.status != BetStatus.Joined) revert BetNotJoined();
        if (block.number <= bet.resolveBlock) revert TooEarly();

        bytes32 hash = blockhash(bet.resolveBlock);
        if (hash == bytes32(0)) {
            // prazo expirou: devolve para os dois
            bet.status = BetStatus.Refunded;
            balanceOf[bet.creator] += bet.amount;
            balanceOf[bet.opponent] += bet.amount;
            emit BetRefunded(betId);
            return;
        }

        Side result = uint256(keccak256(abi.encodePacked(hash, betId))) % 2 == 0
            ? Side.Cara
            : Side.Coroa;

        address winner = result == bet.creatorSide ? bet.creator : bet.opponent;
        uint256 prize = bet.amount * 2;

        bet.status = BetStatus.Resolved;
        bet.winner = winner;
        balanceOf[winner] += prize;

        emit BetResolved(betId, result, winner, prize);
    }

    /// @notice Opcional: o vencedor devolve ao perdedor parte ou todo o valor
    ///         que o perdedor apostou, para o jogo valer só pelo esporte.
    /// @param amount quanto devolver (no máximo o valor apostado pelo perdedor,
    ///        somando devoluções anteriores). Sai do saldo do vencedor no contrato.
    function returnToLoser(uint256 betId, uint256 amount) external {
        Bet storage bet = bets[betId];
        if (bet.status != BetStatus.Resolved) revert BetNotResolved();
        if (msg.sender != bet.winner) revert NotBetWinner();
        if (amount == 0) revert ZeroAmount();
        if (bet.returned + amount > bet.amount) revert ReturnTooHigh();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        address loser = bet.winner == bet.creator ? bet.opponent : bet.creator;

        bet.returned += amount;
        balanceOf[msg.sender] -= amount;
        balanceOf[loser] += amount;

        emit ReturnedToLoser(betId, msg.sender, loser, amount);
    }

    /// @notice Cancela uma aposta que ninguém entrou ainda e devolve o valor.
    function cancelBet(uint256 betId) external {
        Bet storage bet = bets[betId];
        if (bet.status != BetStatus.Open) revert BetNotOpen();
        if (msg.sender != bet.creator) revert NotBetCreator();

        bet.status = BetStatus.Cancelled;
        balanceOf[bet.creator] += bet.amount;

        emit BetCancelled(betId);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit FeeUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
