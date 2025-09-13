;; AIModelDAO - Decentralized AI Model Governance
;; Allows token holders to vote on AI model parameters and funding

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-PROPOSAL (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-CLOSED (err u103))
(define-constant ERR-INSUFFICIENT-QUORUM (err u104))
(define-constant ERR-PROPOSAL-EXECUTED (err u105))
(define-constant ERR-INVALID-DELEGATE (err u106))
(define-constant ERR-TREASURY-INSUFFICIENT (err u107))
(define-constant ERR-MIN-STAKE-REQUIRED (err u108))
(define-constant ERR-INVALID-MODEL-PARAMS (err u109))
(define-constant ERR-COOLDOWN-ACTIVE (err u110))
(define-constant ERR-INVALID-REWARD (err u111))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u112))

(define-data-var proposal-count uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var min-proposal-stake uint u1000)
(define-data-var quorum-threshold uint u30)
(define-data-var voting-period uint u1440)
(define-data-var reward-pool uint u0)
(define-data-var total-staked uint u0)
(define-data-var governance-fee uint u10)

(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    votes-for: uint,
    votes-against: uint,
    end-block: uint,
    executed: bool,
    proposal-type: (string-ascii 30),
    funding-amount: uint,
    target-address: (optional principal),
    model-params: (string-ascii 200),
    priority: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { voted: bool, vote-type: bool, voting-power: uint, timestamp: uint }
)

(define-map dao-tokens
  { holder: principal }
  { balance: uint, staked: uint, last-claim: uint, reputation: uint }
)

(define-map delegations
  { delegator: principal }
  { delegate: principal, voting-power: uint, expiry: uint }
)

(define-map proposal-stakes
  { proposal-id: uint }
  { stake-amount: uint, stake-returned: bool }
)

(define-map governance-settings
  { setting: (string-ascii 30) }
  { value: uint }
)

(define-map member-roles
  { member: principal }
  { role: (string-ascii 20), permissions: uint, reputation-bonus: uint }
)

(define-map model-configurations
  { config-id: uint }
  {
    name: (string-ascii 50),
    parameters: (string-ascii 300),
    performance-metrics: uint,
    active: bool,
    creator: principal
  }
)

(define-map voting-rewards
  { voter: principal, period: uint }
  { rewards-earned: uint, claimed: bool }
)

(define-public (initialize)
  (begin
    (map-set dao-tokens { holder: CONTRACT-OWNER } { balance: u1000000, staked: u0, last-claim: block-height, reputation: u100 })
    (map-set governance-settings { setting: "min-stake" } { value: u1000 })
    (map-set governance-settings { setting: "quorum" } { value: u30 })
    (map-set governance-settings { setting: "voting-period" } { value: u1440 })
    (map-set governance-settings { setting: "cooldown-period" } { value: u144 })
    (map-set member-roles { member: CONTRACT-OWNER } { role: "admin", permissions: u255, reputation-bonus: u50 })
    (var-set treasury-balance u500000)
    (var-set reward-pool u100000)
    (ok true)
  )
)

(define-public (mint-tokens (recipient principal) (amount uint))
  (let
    (
      (current-balance (get balance (get-token-balance recipient)))
      (sender-role (get role (get-member-role tx-sender)))
    )
    (asserts! (is-eq sender-role "admin") ERR-NOT-AUTHORIZED)
    (map-set dao-tokens 
      { holder: recipient }
      { 
        balance: (+ current-balance amount),
        staked: (get staked (get-token-balance recipient)),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance recipient))
      })
    (ok amount)
  )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
  (let
    (
      (sender-balance (get balance (get-token-balance tx-sender)))
    )
    (asserts! (>= sender-balance amount) ERR-NOT-AUTHORIZED)
    (map-set dao-tokens { holder: tx-sender }
      {
        balance: (- sender-balance amount),
        staked: (get staked (get-token-balance tx-sender)),
        last-claim: (get last-claim (get-token-balance tx-sender)),
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (map-set dao-tokens { holder: recipient }
      {
        balance: (+ (get balance (get-token-balance recipient)) amount),
        staked: (get staked (get-token-balance recipient)),
        last-claim: (get last-claim (get-token-balance recipient)),
        reputation: (get reputation (get-token-balance recipient))
      })
    (ok amount)
  )
)

(define-public (stake-tokens (amount uint))
  (let
    (
      (current-balance (get balance (get-token-balance tx-sender)))
      (current-stake (get staked (get-token-balance tx-sender)))
    )
    (asserts! (>= current-balance amount) ERR-NOT-AUTHORIZED)
    (map-set dao-tokens 
      { holder: tx-sender }
      { 
        balance: (- current-balance amount),
        staked: (+ current-stake amount),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (var-set total-staked (+ (var-get total-staked) amount))
    (ok true)
  )
)

(define-public (unstake-tokens (amount uint))
  (let
    (
      (current-stake (get staked (get-token-balance tx-sender)))
      (current-balance (get balance (get-token-balance tx-sender)))
      (last-claim (get last-claim (get-token-balance tx-sender)))
    )
    (asserts! (>= current-stake amount) ERR-NOT-AUTHORIZED)
    (asserts! (> (- block-height last-claim) u144) ERR-COOLDOWN-ACTIVE)
    (map-set dao-tokens 
      { holder: tx-sender }
      { 
        balance: (+ current-balance amount),
        staked: (- current-stake amount),
        last-claim: block-height,
        reputation: (get reputation (get-token-balance tx-sender))
      })
    (var-set total-staked (- (var-get total-staked) amount))
    (ok true)
  )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) 
                              (proposal-type (string-ascii 30)) (funding-amount uint) 
                              (target-address (optional principal)) (model-params (string-ascii 200))
                              (priority uint))
  (let
    (
      (proposal-id (+ (var-get proposal-count) u1))
      (stake-amount (var-get min-proposal-stake))
      (creator-balance (get balance (get-token-balance tx-sender)))
      (creator-reputation (get reputation (get-token-balance tx-sender)))
    )
    (asserts! (>= creator-balance stake-amount) ERR-MIN-STAKE-REQUIRED)
    (asserts! (>= creator-reputation u10) ERR-INSUFFICIENT-REPUTATION)
    (asserts! (<= funding-amount (var-get treasury-balance)) ERR-TREASURY-INSUFFICIENT)
    
    (map-set proposals { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        votes-for: u0,
        votes-against: u0,
        end-block: (+ block-height (var-get voting-period)),
        executed: false,
        proposal-type: proposal-type,
        funding-amount: funding-amount,
        target-address: target-address,
        model-params: model-params,
        priority: priority
      })
    
    (map-set proposal-stakes { proposal-id: proposal-id }
      { stake-amount: stake-amount, stake-returned: false })
    
    (try! (transfer-tokens (as-contract tx-sender) stake-amount))
    (var-set proposal-count proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-INVALID-PROPOSAL))
      (voter-tokens (get-token-balance tx-sender))
      (voting-power (calculate-voting-power tx-sender))
      (has-voted (is-some (map-get? votes { proposal-id: proposal-id, voter: tx-sender })))
    )
    (asserts! (< block-height (get end-block proposal)) ERR-VOTING-CLOSED)
    (asserts! (not has-voted) ERR-ALREADY-VOTED)
    (asserts! (> voting-power u0) ERR-NOT-AUTHORIZED)
    
    (map-set votes { proposal-id: proposal-id, voter: tx-sender }
      { voted: true, vote-type: vote-for, voting-power: voting-power, timestamp: block-height })
    
    (if vote-for
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) }))
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) })))
    
    (try! (update-reputation tx-sender u1))
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-INVALID-PROPOSAL))
      (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
      (quorum-met (>= (* total-votes u100) (* (var-get total-staked) (var-get quorum-threshold))))
      (proposal-passed (> (get votes-for proposal) (get votes-against proposal)))
    )
    (asserts! (>= block-height (get end-block proposal)) ERR-VOTING-CLOSED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXECUTED)
    (asserts! quorum-met ERR-INSUFFICIENT-QUORUM)
    (asserts! proposal-passed ERR-NOT-AUTHORIZED)
    
    (map-set proposals { proposal-id: proposal-id }
      (merge proposal { executed: true }))
    
    (if (> (get funding-amount proposal) u0)
      (begin
        (var-set treasury-balance (- (var-get treasury-balance) (get funding-amount proposal)))
        (if (is-some (get target-address proposal))
          (try! (as-contract (stx-transfer? (get funding-amount proposal) 
                                         tx-sender 
                                         (unwrap-panic (get target-address proposal)))))
          true))
      true)
    
    (try! (return-proposal-stake proposal-id))
    (try! (update-reputation (get creator proposal) u5))
    (ok true)
  )
)

(define-public (delegate-voting-power (delegate principal) (expiry-blocks uint))
  (let
    (
      (delegator-tokens (get-token-balance tx-sender))
      (voting-power (+ (get staked delegator-tokens) (/ (get balance delegator-tokens) u2)))
    )
    (asserts! (> voting-power u0) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq delegate tx-sender)) ERR-INVALID-DELEGATE)
    
    (map-set delegations { delegator: tx-sender }
      { delegate: delegate, voting-power: voting-power, expiry: (+ block-height expiry-blocks) })
    (ok true)
  )
)

(define-public (register-model-config (name (string-ascii 50)) (parameters (string-ascii 300)))
  (let
    (
      (config-id (+ (var-get proposal-count) u1))
      (creator-reputation (get reputation (get-token-balance tx-sender)))
    )
    (asserts! (>= creator-reputation u25) ERR-INSUFFICIENT-REPUTATION)
    
    (map-set model-configurations { config-id: config-id }
      {
        name: name,
        parameters: parameters,
        performance-metrics: u0,
        active: false,
        creator: tx-sender
      })
    
    (try! (update-reputation tx-sender u3))
    (ok config-id)
  )
)

(define-public (update-model-performance (config-id uint) (metrics uint))
  (let
    (
      (config (unwrap! (map-get? model-configurations { config-id: config-id }) ERR-INVALID-MODEL-PARAMS))
      (sender-role (get role (get-member-role tx-sender)))
    )
    (asserts! (or (is-eq (get creator config) tx-sender) 
                  (is-eq sender-role "admin")) ERR-NOT-AUTHORIZED)
    
    (map-set model-configurations { config-id: config-id }
      (merge config { performance-metrics: metrics }))
    
    (if (> metrics u80)
      (try! (distribute-model-reward (get creator config) u100))
      (ok u0))
  )
)

(define-public (activate-model (config-id uint))
  (let
    (
      (config (unwrap! (map-get? model-configurations { config-id: config-id }) ERR-INVALID-MODEL-PARAMS))
      (sender-role (get role (get-member-role tx-sender)))
    )
    (asserts! (is-eq sender-role "admin") ERR-NOT-AUTHORIZED)
    (asserts! (> (get performance-metrics config) u70) ERR-INVALID-MODEL-PARAMS)
    
    (map-set model-configurations { config-id: config-id }
      (merge config { active: true }))
    
    (try! (distribute-model-reward (get creator config) u500))
    (ok true)
  )
)

(define-public (claim-voting-rewards (period uint))
  (let
    (
      (rewards (unwrap! (map-get? voting-rewards { voter: tx-sender, period: period }) ERR-INVALID-REWARD))
      (reward-amount (get rewards-earned rewards))
    )
    (asserts! (not (get claimed rewards)) ERR-INVALID-REWARD)
    (asserts! (>= (var-get reward-pool) reward-amount) ERR-TREASURY-INSUFFICIENT)
    
    (map-set voting-rewards { voter: tx-sender, period: period }
      (merge rewards { claimed: true }))
    
    (var-set reward-pool (- (var-get reward-pool) reward-amount))
    (try! (mint-tokens tx-sender reward-amount))
    (ok reward-amount)
  )
)

(define-public (distribute-staking-rewards)
  (let
    (
      (sender-role (get role (get-member-role tx-sender)))
      (total-rewards u10000)
      (user-stake (get staked (get-token-balance tx-sender)))
      (user-reward (/ (* user-stake total-rewards) (var-get total-staked)))
    )
    (asserts! (is-eq sender-role "admin") ERR-NOT-AUTHORIZED)
    (asserts! (>= (var-get reward-pool) user-reward) ERR-TREASURY-INSUFFICIENT)
    (asserts! (> user-stake u0) ERR-NOT-AUTHORIZED)
    
    (var-set reward-pool (- (var-get reward-pool) user-reward))
    (try! (mint-tokens tx-sender user-reward))
    (ok user-reward)
  )
)
