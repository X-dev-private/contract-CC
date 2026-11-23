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
