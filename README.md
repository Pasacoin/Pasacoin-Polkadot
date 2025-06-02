# Pasanaku Smart Contract

A decentralized implementation of the traditional Andean "Pasanaku" rotating savings and credit association (ROSCA) system on the blockchain.

## Overview

Pasanaku is a traditional communal savings system where a group of people contribute fixed amounts periodically, and each participant takes turns receiving the total collected amount. This smart contract implements this system in a transparent and trustless way on the blockchain.

## Features

- Create savings groups (salas) with customizable:
  - Number of participants
  - Contribution amount
  - Start date
- Invite participants to join a group
- Random assignment of participant turns
- Automated collection and distribution of funds
- Transparent transaction history
- Built-in safety checks and validations

## Contract Structure

### Key Components

- `Sala`: Main structure that holds group information and state
- `Participante`: Structure for participant data
- `Transaccion`: Structure for tracking contributions and payments

### Main Functions

1. Group Management
   - `crearSala`: Create a new savings group
   - `invitarParticipantes`: Invite members to join
   - `unirseASala`: Join an existing group
   - `realizarSorteo`: Randomly assign participant turns

2. Financial Operations
   - `realizarAporte`: Make a contribution
   - `retirarFondos`: Withdraw available funds
   
3. Query Functions
   - `obtenerSala`: Get group details
   - `obtenerParticipantes`: List participants
   - `obtenerTransacciones`: View transaction history
   - `obtenerPendienteRetiro`: Check pending withdrawals
   - `esInvitado`: Check if address is invited
   - `obtenerTurnoUsuario`: Get participant's turn number

## Usage Example

```solidity
// 1. Create a new group
pasanaku.crearSala(
    "grupo1",        // Group ID
    5,              // Number of participants
    1 ether,        // Contribution amount
    1672531200      // Start date (Unix timestamp)
);

// 2. Invite participants
pasanaku.invitarParticipantes("grupo1", [address1, address2, address3, address4]);

// 3. Participants join
pasanaku.unirseASala("grupo1");

// 4. Assign turns randomly
pasanaku.realizarSorteo("grupo1");

// 5. Make contributions
pasanaku.realizarAporte{value: 1 ether}("grupo1");

// 6. Withdraw funds when available
pasanaku.retirarFondos("grupo1");