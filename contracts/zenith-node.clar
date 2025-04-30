;; zenith-node.clar
;; A contract that simulates a lightweight blockchain environment for testing Clarity contracts
;;
;; This contract creates a simulated blockchain environment with controllable parameters
;; to help developers test their smart contracts with predictable outcomes. It allows
;; manipulation of virtual block height, timestamps, and tracks transaction history.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ACCOUNT-NOT-REGISTERED (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-PARAMETER (err u103))
(define-constant ERR-ACCOUNT-ALREADY-EXISTS (err u104))
(define-constant ERR-TX-NOT-FOUND (err u105))

;; Contract owner for admin operations
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures for the simulated blockchain environment
(define-data-var current-block-height uint u1)
(define-data-var current-timestamp uint (default-to u0 block-time))
(define-data-var genesis-timestamp uint (default-to u0 block-time))
(define-data-var is-paused bool false)

;; Data structure for registered test accounts
(define-map accounts 
  { address: principal }
  { balance: uint, nonce: uint, created-at-block: uint }
)

;; Data structure for transaction history
(define-map transactions 
  { tx-id: uint }
  { 
    sender: principal, 
    recipient: principal, 
    amount: uint, 
    block-height: uint,
    timestamp: uint,
    success: bool,
    memo: (optional (string-ascii 256))
  }
)

;; Counter for transaction IDs
(define-data-var tx-counter uint u0)

;; Private functions

;; Check if the caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Check if an account is registered
(define-private (is-account-registered (address principal))
  (is-some (map-get? accounts {address: address}))
)

;; Get the next transaction ID and increment the counter
(define-private (get-next-tx-id)
  (let ((current-tx-id (var-get tx-counter)))
    (var-set tx-counter (+ current-tx-id u1))
    current-tx-id
  )
)

;; Read-only functions

;; Get the current block height
(define-read-only (get-block-height)
  (var-get current-block-height)
)

;; Get the current timestamp
(define-read-only (get-timestamp)
  (var-get current-timestamp)
)

;; Check if the simulation environment is paused
(define-read-only (get-paused-state)
  (var-get is-paused)
)

;; Get the genesis timestamp when the environment was started
(define-read-only (get-genesis-timestamp)
  (var-get genesis-timestamp)
)

;; Get the account details for a registered test account
(define-read-only (get-account-details (address principal))
  (default-to 
    {balance: u0, nonce: u0, created-at-block: u0}
    (map-get? accounts {address: address})
  )
)

;; Get the balance of a registered test account
(define-read-only (get-balance (address principal))
  (default-to
    u0
    (get balance (map-get? accounts {address: address}))
  )
)

;; Get the transaction details for a specific transaction ID
(define-read-only (get-transaction (tx-id uint))
  (map-get? transactions {tx-id: tx-id})
)

;; Public functions

;; Initialize or reset the simulated environment
(define-public (init-environment)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set current-block-height u1)
    (var-set current-timestamp (default-to u0 block-time))
    (var-set genesis-timestamp (default-to u0 block-time))
    (var-set is-paused false)
    (var-set tx-counter u0)
    (ok true)
  )
)

;; Register a new test account with an initial balance
(define-public (register-account (address principal) (initial-balance uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-account-registered address)) ERR-ACCOUNT-ALREADY-EXISTS)
    
    (map-set accounts
      {address: address}
      {
        balance: initial-balance,
        nonce: u0,
        created-at-block: (var-get current-block-height)
      }
    )
    (ok true)
  )
)

;; Advance the block height by a specified number of blocks
(define-public (advance-blocks (blocks uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> blocks u0) ERR-INVALID-PARAMETER)
    (asserts! (not (var-get is-paused)) ERR-INVALID-PARAMETER)
    
    ;; Update block height and timestamp
    ;; Assume each block takes ~10 minutes (600 seconds) on average
    (var-set current-block-height (+ (var-get current-block-height) blocks))
    (var-set current-timestamp (+ (var-get current-timestamp) (* blocks u600)))
    
    (ok (var-get current-block-height))
  )
)

;; Set the timestamp explicitly (useful for time-sensitive contract testing)
(define-public (set-timestamp (new-timestamp uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get is-paused)) ERR-INVALID-PARAMETER)
    (asserts! (>= new-timestamp (var-get current-timestamp)) ERR-INVALID-PARAMETER)
    
    (var-set current-timestamp new-timestamp)
    (ok (var-get current-timestamp))
  )
)

;; Pause/unpause the simulated environment
(define-public (set-pause-state (paused bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set is-paused paused)
    (ok paused)
  )
)

;; Simulate a transfer between two test accounts
(define-public (simulate-transfer (sender principal) (recipient principal) (amount uint) (memo (optional (string-ascii 256))))
  (let (
    (sender-details (get-account-details sender))
    (recipient-details (get-account-details recipient))
    (tx-id (get-next-tx-id))
    (current-height (var-get current-block-height))
    (current-time (var-get current-timestamp))
    (success-result (and (is-account-registered sender) 
                         (is-account-registered recipient)
                         (>= (get balance sender-details) amount)))
  )
    (asserts! (not (var-get is-paused)) ERR-INVALID-PARAMETER)
    
    ;; Record the transaction regardless of success
    (map-set transactions
      {tx-id: tx-id}
      {
        sender: sender,
        recipient: recipient,
        amount: amount,
        block-height: current-height,
        timestamp: current-time,
        success: success-result,
        memo: memo
      }
    )
    
    ;; If transaction conditions are met, update balances
    (if success-result
      (begin
        (map-set accounts
          {address: sender}
          {
            balance: (- (get balance sender-details) amount),
            nonce: (+ (get nonce sender-details) u1),
            created-at-block: (get created-at-block sender-details)
          }
        )
        (map-set accounts
          {address: recipient}
          {
            balance: (+ (get balance recipient-details) amount),
            nonce: (get nonce recipient-details),
            created-at-block: (get created-at-block recipient-details)
          }
        )
        (ok tx-id)
      )
      (err (if (not (is-account-registered sender))
             ERR-ACCOUNT-NOT-REGISTERED
             (if (not (is-account-registered recipient))
               ERR-ACCOUNT-NOT-REGISTERED
               ERR-INSUFFICIENT-BALANCE
             )
           )
      )
    )
  )
)

;; Fund a test account with additional tokens (for testing purposes)
(define-public (fund-account (address principal) (amount uint))
  (let (
    (account-details (get-account-details address))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-account-registered address) ERR-ACCOUNT-NOT-REGISTERED)
    (asserts! (not (var-get is-paused)) ERR-INVALID-PARAMETER)
    
    (map-set accounts
      {address: address}
      {
        balance: (+ (get balance account-details) amount),
        nonce: (get nonce account-details),
        created-at-block: (get created-at-block account-details)
      }
    )
    (ok true)
  )
)

;; Mine a single block (shorthand for advance-blocks with a parameter of 1)
(define-public (mine-block)
  (advance-blocks u1)
)

;; Reset an account to a clean state (optionally with a new balance)
(define-public (reset-account (address principal) (new-balance uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-account-registered address) ERR-ACCOUNT-NOT-REGISTERED)
    
    (map-set accounts
      {address: address}
      {
        balance: new-balance,
        nonce: u0,
        created-at-block: (var-get current-block-height)
      }
    )
    (ok true)
  )
)