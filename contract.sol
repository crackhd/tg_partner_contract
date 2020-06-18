pragma solidity ^0.4.16;
pragma experimental ABIEncoderV2;

contract Token {

    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}



contract StandardToken is Token {

    mapping (address => uint256) balances;                          // token balances per user

    mapping (address => mapping (address => uint256)) allowed;      // ERC20 complience mostly
                                                                    // amount of tokens user allowed to spend from his balance
                                                                    // to another user

    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        //if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            emit Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            emit Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }
}


//name this contract whatever you'd like
contract RewardToken is StandardToken {

    // Challenge status is a enum
    enum ChallengeStatus {
        INVALID,        // Status by default is invalid
        NEW,            // An initial status for created challenge
        CONFIRMED,      // Challenge has been confirmed by bot as in progress
        FINISHED,       // Challenge has been finished by bot
        ERROR,          // Challenge resulted into an error and is aborted
        TIMEOUT         // challenge request timed out
    }

    // struct with dynamic data of the challenge
    struct ChallengeData {
        uint256 confirmedAt;                            // timestamp
        uint256 finishedAt;                             // timestamp

        ChallengeStatus status;                         // current status
        uint256 pointsBefore;                           // score of the user before
        uint256 pointsAfter;                            // and at the end of the challenge
        string error;                                   // in case of an error, hold description
        uint256 reward;                                 // amount of tokens assigned to sender as a result of the challenge

        uint256 etherCostService;                       // approximate total gas charges BOTS spent on this request
    }

    // Challenge is a request to bot(s) from a user
    struct Challenge {
        uint256 id;                                     // unique identifier of the challenge
        address user;                                   // request owner
        uint256 createdAt;                              // timestamp

        uint32 flags;                                   // custom flags (reserved)
        string group;                                   // group designates the target of the challenge
        uint32 resource;                                // specific request of challenge (part of the group)

        ChallengeData data;                             // struct with dynamic data of the challenge

        uint256 userEtherCost;                          // gas cost per request of user (spent)
    }

    // Rule defines amount of reward starting from some number of points
    struct Rule {
        string group;                               // group name (if needed) which the rule is effective for
        uint256 threshold;                          // minimal amount of points for rule to be applied
        uint256 rewardForPoint;                     // how much tokens to give as reward per point
    }

    address public ceo;                             // owner of contract, has the abillity to withdraw ether from the contract (if needed),
                                                    // modify array of authorized bots
                                                    // and update list of authorized groups
    mapping (address => bool) public bots;          // authorized bots who can respond to challenge requests and update their status

    string[] public groups;                             // authorized groups for future challenges

    mapping (address => uint256) public donations;      // amount of ether sent by a user (excl. gas charges)

    mapping (uint256 => Challenge) public challenges;   // Gets challenge by id

    mapping (address => uint256) public userChallenge;  // active challenge id by user;
                                                        // a user cannot have more than one ongoing challenge

    uint256 public numChallenges;                       // total number of created challenges

    uint256 public totalOwnedTokens;                    // total number of tokens which are owne (not bank)

    uint256 public minBankForChallenge;                 // minimal amount of bank needed to start new challenges, as set by CEO

    uint256 public duration;                            // duration of a challenge, as set by the ceo

    Rule[] public rules;                                // rewarding rules, as set by CEO
                                                        // this array MUST be sorted from defining higher to lower point threshold values

    uint256 public weiPerToken;                         // how much ether we give or take for a token, as set by CEO

    uint256 public requestTimeout;                      // maximum time before challenge is failed without confirmation or after confirmation
                                                        // and a refund is available, as set by CEO

    mapping (address => uint256) public etherCostService;      // for every user, keep costs from service side before the withdrawal (sell)

    bool public serviceCostsEnabled;                    // determines whether users will be charged for gas costs of service bots, as set by CEO

    mapping (address => uint256) public etherUserCompensation;     // for ever user, if challenge request has failed, we will refund gasprice cost if requested

    /* Public variables of the token */

    // ERC20 complience mostly

    /*
    NOTE:
    The following variables are OPTIONAL vanities. One does not have to include them.
    They allow one to customise the token contract & in no way influences the core functionality.
    Some wallets/interfaces might not even bother to look at this information.
    */
    string public name;                   //fancy name: eg Simon Bucks
    uint8 public decimals;                //How many decimals to show. ie. There could 1000 base units with 3 decimals. Meaning 0.980 SBX = 980 base units. It's like comparing 1 wei to 1 ether.
    string public symbol;                 //An identifier: eg SBX
    string public version = 'H1.0';       //human 0.1 standard. Just an arbitrary versioning scheme.

    //
    // CHANGE THESE VALUES FOR YOUR TOKEN
    //

    //make sure this function name matches the contract name above. So if you're token is called TutorialToken, make sure the //contract name above is also TutorialToken instead of ERC20Token

    constructor(uint256 _weiPerToken, uint256 _minBankForChallenge, uint256 _rewardForPoint, uint256 _duration, uint256 _requestTimeout, bool _serviceCostsEnabled) public payable
    {
        ceo = msg.sender;                       // hire CEO
        donations[msg.sender] = msg.value;      // ceo donation excl. gas cost

        weiPerToken = _weiPerToken;
        minBankForChallenge = _minBankForChallenge;
        duration = _duration;
        requestTimeout = _requestTimeout;
        serviceCostsEnabled = _serviceCostsEnabled;

        // Iniital rule
        rules.push(Rule({
            group: "",
            threshold: 0,
            rewardForPoint: _rewardForPoint
        }));

        name = "Reward Token";                  // Set the name for display purposes
        decimals = 2;                           // Amount of decimals for display purposes
        symbol = "RWRD";                        // Set the symbol for display purposes

        updateSupplyAndBank();
    }

    /// @return total amount of tokens (directly tied to the contract balance)
    function totalSupply() constant returns (uint256 supply) {
        return address(this).balance / weiPerToken;
    }

    /// @return total amount of tokens which are supported by ether, but do not have any owner (thus usable for new rewards)
    function totalBank() constant returns (uint256 bank) {
        return totalSupply() - totalOwnedTokens;
    }

    // if ether is sent to this address, accept it - increases totalSupply, remembering user donation
    function () public payable {
        updateSupplyAndBank();
    }

    // Equal to send money to the contract directly - increases totalSupply, remembering user donation
    function deposit() public payable {
        updateSupplyAndBank();
    }

    /* Approves and then calls the receiving contract */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);

        //call the receiveApproval function on the contract you want to be notified. This crafts the function signature manually so one doesn't have to include a contract in here just for this.
        //receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData)
        //it is assumed that when does this that the call *should* succeed, otherwise one would use vanilla approve instead.
        if(!_spender.call(bytes4(bytes32(sha3("receiveApproval(address,uint256,address,bytes)"))), msg.sender, _value, this, _extraData)) { revert(); }
        return true;
    }

    function newChallenge(string group, uint32 resource, uint32 flags) public payable  {
        if (totalBank() < minBankForChallenge) {
            revert("Low on supply for new challenge (safety check)");
        }
        if (hasActiveChallenge(msg.sender)) {
            revert("You already have an ongoing challenge request");
        }
        if (bytes(group).length == 0 || resource <= 0) {
            revert("Invalid challenge request");
        }

        challenges[numChallenges] = Challenge({
            id: numChallenges,
            user: msg.sender,
            createdAt: now,
            flags: flags,
            group: group,
            resource: resource,
            data: ChallengeData({
                confirmedAt: 0,
                finishedAt: 0,
                status: ChallengeStatus.NEW,
                pointsBefore: 0,
                pointsAfter: 0,
                error: "",
                reward: 0,
                etherCostService: 0
            }),
            userEtherCost: 0
        });

        userChallenge[msg.sender] = numChallenges;
        emit ChallengeRequest(numChallenges, msg.sender, group);

        numChallenges++;

        updateSupplyAndBank();

        challenges[numChallenges - 1].userEtherCost = tx.gasprice + 21000;
    }

    // New challenge is created
    event ChallengeRequest(uint256 indexed _id, address indexed _user, string _group);

    // Challenge status was updated
    event ChallengeUpdate(uint256 indexed _id, ChallengeStatus indexed _status, uint256 _reward);

    // Sell converts user token(s) to ether and sends ether to user
    // This will decreatse both totalBank() and totalSupply()
    // It will subtract the amount of commission for service (gas price from our side)
    // It will add the amount of compensation
    // If user has an ongoing challenge, it will be checked for timeout
    // (timeout compensation will be included into transfer of the function)
    // Allowed amounts are 0 and higher.
    function sell(uint256 requestTokens) public {
        if(requestTokens < 0) {
            revert("Invalid amount of tokens");
        }
        if (requestTokens > balances[msg.sender]) {
            revert("You do not have enough tokens on your balance");
        }
        if (msg.value > 0) {
            revert("Do not send ether with this call");
        }

        uint256 requestEther = requestTokens * weiPerToken;

        if (hasActiveChallenge(msg.sender)) {
            failChallengeIfTimeout(userChallenge[msg.sender]);
        }

        if(serviceCostsEnabled) {
            requestEther -= etherCostService[msg.sender];
        }
        etherCostService[msg.sender] = 0;

        requestEther += etherUserCompensation[msg.sender];
        etherUserCompensation[msg.sender] = 0;

        if (requestEther < 0) {
            revert("The balance is too low to add the service costs as commission (compensations excluded)");
        }

        balances[msg.sender] -= requestTokens;
        totalOwnedTokens -= requestTokens;

        msg.sender.transfer(requestEther);
        emit Transfer(msg.sender, address(this), requestTokens);
    }

    // Any user can buy theirself tokens in exchange to ether
    function buy() public payable {
        donations[msg.sender] -= msg.value;

        uint256 tokens = msg.value / weiPerToken;

        balances[msg.sender] += tokens;
        totalOwnedTokens += tokens;

        emit Transfer(address(this), msg.sender, tokens);
    }

    // BOT ONLY: Marks challenge failed with a message
    function botFailChallenge(uint256 _id, string error) public payable {
        uint256 startGas = gasleft();

        if (!bots[msg.sender]) {
            revert();
        }

        if (challenges[_id].data.status != ChallengeStatus.NEW) {
            if (challenges[_id].data.status != ChallengeStatus.CONFIRMED) {
                revert();
            }
        }

        challenges[_id].data.status = ChallengeStatus.ERROR;
        challenges[_id].data.finishedAt = now;

        address user = challenges[_id].user;
        userChallenge[user] = 0;
        etherUserCompensation[user] += challenges[_id].userEtherCost;

        emit ChallengeUpdate(_id, ChallengeStatus.ERROR, 0);

        updateSupplyAndBank();
        saveChallengeServiceCosts(_id, startGas);
    }

    // BOT ONLY: Marks challenge as started (confirmed)
    function botConfirmChallenge(uint256 _id, uint256 pointsBefore) public payable {
        uint256 startGas = gasleft();

        if (!bots[msg.sender]) {
            revert();
        }

        if (challenges[_id].data.status != ChallengeStatus.NEW) {
            revert();
        }

        if(!failChallengeIfTimeout(_id)) {
            challenges[_id].data.status = ChallengeStatus.CONFIRMED;
            challenges[_id].data.pointsBefore = pointsBefore;
            challenges[_id].data.confirmedAt = now;

            emit ChallengeUpdate(_id, ChallengeStatus.CONFIRMED, 0);
        }

        updateSupplyAndBank();
        saveChallengeServiceCosts(_id, startGas);
    }

    // BOT ONLY: Marks challenge as finished (done) and triggers reward for user
    function botFinishChallenge(uint256 _id, uint256 pointsAfter) public payable {
        uint256 startGas = gasleft();

        if (!bots[msg.sender]) {
            revert();
        }

        if (challenges[_id].data.status != ChallengeStatus.CONFIRMED) {
            revert();
        }

        if(!failChallengeIfTimeout(_id)) {
            address user = challenges[_id].user;

            challenges[_id].data.status = ChallengeStatus.FINISHED;
            challenges[_id].data.pointsAfter = pointsAfter;
            challenges[_id].data.finishedAt = now;

            uint256 points = challenges[_id].data.pointsAfter - challenges[_id].data.pointsBefore;
            uint256 tokenAmount = rewardForPoints(points, challenges[_id].group);

            challenges[_id].data.reward = tokenAmount;

            balances[user] += tokenAmount;
            totalOwnedTokens += tokenAmount;

            userChallenge[challenges[_id].user] = 0;
            emit ChallengeUpdate(_id, ChallengeStatus.FINISHED, tokenAmount);
            emit Transfer(address(this), user, tokenAmount);
        }

        updateSupplyAndBank();
        saveChallengeServiceCosts(_id, startGas);
    }

    // CEO ONLY: set restrictions and rewards
    function ceoUpdate(uint256 _minBankForChallenge, uint256 _duration, uint256 _weiPerToken, uint256 _requestTimeout, bool _serviceCostsEnabled) public payable  {
        if (msg.sender != ceo) {
            revert();
        }

        minBankForChallenge = _minBankForChallenge;
        duration = _duration;
        weiPerToken = _weiPerToken;
        requestTimeout = _requestTimeout;
        serviceCostsEnabled = _serviceCostsEnabled;

        updateSupplyAndBank();
    }

    // CEO ONLY: Updates the rules of reward system
    function ceoUpdateRules(Rule[] _rules) public payable {
        if (msg.sender != ceo) {
            revert();
        }

        for (uint i = 0; i < _rules.length; i++) {
          rules[i] = _rules[i];
        }

        for (i = _rules.length; i < rules.length; i++) {
          delete rules[i];
        }

        updateSupplyAndBank();
    }

    // CEO ONLY: remove or add authorization of bots
    function ceoAuthBots(bool auth, address[] _bots) public payable  {
        if (msg.sender != ceo) {
            revert();
        }

        for (uint i = 0; i < _bots.length; i++) {
            bots[_bots[i]] = auth;
        }

        updateSupplyAndBank();
    }

    // CEO ONLY: moves tokens to user's balance
    function ceoRewardFromBank(address user, uint256 amountTokens) public payable {
        if (msg.sender != ceo) {
            revert();
        }

        balances[user] += amountTokens;
        totalOwnedTokens += amountTokens;

        emit Transfer(address(this), user, amountTokens);

        updateSupplyAndBank();
    }

    // Returns true if strings are equal (unsafe!)
    function compareStrings (string memory a, string memory b) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))) );
    }

    // Calculates reward according to the rules set by CEO
    function rewardForPoints(uint256 points, string group) public constant returns (uint256) {
        uint256 result = 0;

        for (uint i = 0; i < rules.length; i++) {
            if (points > rules[i].threshold) {
                if (bytes(rules[i].group).length == 0 || compareStrings(group, rules[i].group)) {
                    uint256 pointsAbove = (points - rules[i].threshold);
                    result += pointsAbove * rules[i].rewardForPoint;
                    points -= pointsAbove;
                }
            }
        }

        return result + points;
    }

    // Mark challenge as timed out and emits event
    function onChallengeTimeout(uint256 _id) private {
        challenges[_id].data.status = ChallengeStatus.TIMEOUT;

        address user = challenges[_id].user;

        userChallenge[user] = 0;

        etherUserCompensation[user] += challenges[_id].userEtherCost;

        challenges[_id].data.finishedAt = now;

        emit ChallengeUpdate(_id, ChallengeStatus.TIMEOUT, 0);
    }

    // Checks if challenge has timed out and fails it if so. Returns true if challenge has timed out
    function failChallengeIfTimeout(uint256 _id) private returns (bool) {
        if (challenges[_id].data.status == ChallengeStatus.NEW) {
            if (now >= (challenges[_id].createdAt + requestTimeout)) {
                onChallengeTimeout(_id);
                return false;
            }
        }

        if (challenges[_id].data.status == ChallengeStatus.CONFIRMED) {
            if (now >= (challenges[_id].data.confirmedAt + requestTimeout)) {
                onChallengeTimeout(_id);
                return true;
            }
        }

        return false;
    }

    // Saves the cost of current transaction as future commission in the payout to creator of the challenge
    function saveChallengeServiceCosts(uint256 _id, uint256 startGas) private {
        challenges[_id].data.etherCostService += commission;

        if(serviceCostsEnabled) {
            uint256 gasUsed = startGas - gasleft();
            uint256 commission = (gasUsed * tx.gasprice) + 21000 + msg.value;
            etherCostService[challenges[_id].user] += commission;
        } else {
            etherCostService[challenges[_id].user] = 0;
        }
    }

    // Checks whether user has an ongoing challenge request at the moment
    function hasActiveChallenge(address user) constant public returns (bool) {
        uint256 _id = userChallenge[user];
        return challenges[_id].user == user && (
            challenges[_id].data.status == ChallengeStatus.NEW ||
            challenges[_id].data.status == ChallengeStatus.CONFIRMED
        );
    }

    // Saves value of current transaction as new bamk money (if any)
    function updateSupplyAndBank() private {
        donations[msg.sender] += msg.value;
    }
}
