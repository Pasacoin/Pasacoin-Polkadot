// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Pasanaku {
    // Custom Errors
    error SalaYaExiste();
    error SalaNoExiste();
    error SalaFinalizada();
    error SoloOrganizador();
    error NoInvitado();
    error YaEsParticipante();
    error SalaLlena();
    error SorteoYaRealizado();
    error SorteoNoRealizado();
    error MontoIncorrecto();
    error YaAporto();
    error YaRecibio();
    error TransferenciaFallida();

    struct Participante {
        address wallet; 
        uint8 numTurno;
        bool haRecibido;
        bool haAportadoRondaActual;
    }

    struct Transaccion {
        address from;
        address to;
        uint monto;
        uint32 fecha;
        uint8 ronda;
        bool esPago;
    }

    struct Sala {
        address organizador;
        uint montoAportar;
        uint8 numeroParticipantes;
        uint8 rondaActual;
        uint32 fechaInicio;
        bool salaFinalizada;
        bool sorteoRealizado;
        uint balanceRondaActual;
        
        mapping(address => bool) invitados;
        Participante[] participantes;
        Transaccion[] transacciones;
        mapping(address => uint) pendienteRetiro;
    }

    mapping(string => Sala) private salas;
    mapping(address => string[]) private salasUsuario;

    event SalaCreada(string indexed hashId, address indexed organizador);
    event ParticipanteUnido(string indexed hashId, address indexed participante);
    event SorteoRealizado(string indexed hashId);
    event AporteRealizado(string indexed hashId, address indexed participante, uint monto);
    event PagoDisponible(string indexed hashId, address indexed beneficiario, uint monto);

    modifier soloOrganizador(string calldata hashId) {
        if (salas[hashId].organizador != msg.sender) revert SoloOrganizador();
        _;
    }

    modifier salaExiste(string calldata hashId) {
        if (salas[hashId].organizador == address(0)) revert SalaNoExiste();
        _;
    }

    modifier salaActiva(string calldata hashId) {
        if (salas[hashId].salaFinalizada) revert SalaFinalizada();
        _;
    }

    function crearSala(
        string calldata hashId,
        uint8 numeroParticipantes,
        uint montoAportar,
        uint32 fechaInicio
    ) external {
        if (salas[hashId].organizador != address(0)) revert SalaYaExiste();
        
        Sala storage nuevaSala = salas[hashId];
        nuevaSala.organizador = msg.sender;
        nuevaSala.montoAportar = montoAportar;
        nuevaSala.numeroParticipantes = numeroParticipantes;
        nuevaSala.fechaInicio = fechaInicio;
        nuevaSala.rondaActual = 1;
        nuevaSala.invitados[msg.sender] = true;

        salasUsuario[msg.sender].push(hashId);
        emit SalaCreada(hashId, msg.sender);
    }

    function invitarParticipantes(
        string calldata hashId,
        address[] calldata participantesInvitados
    ) external salaExiste(hashId) salaActiva(hashId) soloOrganizador(hashId) {
        if (salas[hashId].sorteoRealizado) revert SorteoYaRealizado();
        
        Sala storage sala = salas[hashId];
        for (uint i = 0; i < participantesInvitados.length; i++) {
            sala.invitados[participantesInvitados[i]] = true;
        }
    }

    function unirseASala(string calldata hashId) external salaExiste(hashId) salaActiva(hashId) {
        Sala storage sala = salas[hashId];
        if (!sala.invitados[msg.sender]) revert NoInvitado();
        if (sala.participantes.length >= sala.numeroParticipantes) revert SalaLlena();
        if (sala.sorteoRealizado) revert SorteoYaRealizado();
        if (_esParticipante(hashId, msg.sender)) revert YaEsParticipante();

        sala.participantes.push(Participante({
            wallet: msg.sender,
            numTurno: 0,
            haRecibido: false,
            haAportadoRondaActual: false
        }));

        salasUsuario[msg.sender].push(hashId);
        emit ParticipanteUnido(hashId, msg.sender);
    }

    function realizarSorteo(string calldata hashId) external salaExiste(hashId) salaActiva(hashId) soloOrganizador(hashId) {
        Sala storage sala = salas[hashId];
        if (sala.sorteoRealizado) revert SorteoYaRealizado();

        uint len = sala.participantes.length;
        bool[] memory usados = new bool[](len + 1);
        
        for (uint i = 0; i < len; i++) {
            uint numeroAleatorio;
            do {
                numeroAleatorio = (uint(keccak256(abi.encodePacked(
                    block.timestamp, 
                    block.prevrandao, 
                    msg.sender, 
                    i
                ))) % len) + 1;
            } while (usados[numeroAleatorio]);
            
            usados[numeroAleatorio] = true;
            sala.participantes[i].numTurno = uint8(numeroAleatorio);
        }

        sala.sorteoRealizado = true;
        emit SorteoRealizado(hashId);
    }

    function realizarAporte(string calldata hashId) external payable salaExiste(hashId) salaActiva(hashId) {
        Sala storage sala = salas[hashId];
        if (!sala.sorteoRealizado) revert SorteoNoRealizado();
        if (msg.value != sala.montoAportar) revert MontoIncorrecto();
        
        uint participanteIndex = _obtenerIndiceParticipante(hashId, msg.sender);
        if (sala.participantes[participanteIndex].haAportadoRondaActual) revert YaAporto();

        sala.participantes[participanteIndex].haAportadoRondaActual = true;
        sala.balanceRondaActual += msg.value;

        sala.transacciones.push(Transaccion({
            from: msg.sender,
            to: address(this),
            monto: msg.value,
            fecha: uint32(block.timestamp),
            ronda: sala.rondaActual,
            esPago: false
        }));

        emit AporteRealizado(hashId, msg.sender, msg.value);

        if (_todosHanAportado(hashId)) {
            _procesarPago(hashId);
        }
    }

    function _procesarPago(string memory hashId) private {
        Sala storage sala = salas[hashId];
        
        address beneficiario;
        uint beneficiarioIndex;
        for (uint i = 0; i < sala.participantes.length; i++) {
            if (sala.participantes[i].numTurno == sala.rondaActual) {
                beneficiario = sala.participantes[i].wallet;
                beneficiarioIndex = i;
                break;
            }
        }

        if (sala.participantes[beneficiarioIndex].haRecibido) revert YaRecibio();

        uint montoTotal = sala.balanceRondaActual;
        sala.participantes[beneficiarioIndex].haRecibido = true;
        sala.balanceRondaActual = 0;
        
        sala.pendienteRetiro[beneficiario] += montoTotal;

        sala.transacciones.push(Transaccion({
            from: address(this),
            to: beneficiario,
            monto: montoTotal,
            fecha: uint32(block.timestamp),
            ronda: sala.rondaActual,
            esPago: true
        }));

        emit PagoDisponible(hashId, beneficiario, montoTotal);
        _prepararSiguienteRonda(hashId);
    }

    function retirarFondos(string calldata hashId) external salaExiste(hashId) {
        Sala storage sala = salas[hashId];
        uint monto = sala.pendienteRetiro[msg.sender];
        if (monto == 0) return;

        sala.pendienteRetiro[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: monto}("");
        if (!success) {
            sala.pendienteRetiro[msg.sender] = monto;
            revert TransferenciaFallida();
        }
    }

    function _prepararSiguienteRonda(string memory hashId) private {
        Sala storage sala = salas[hashId];
        
        for (uint i = 0; i < sala.participantes.length; i++) {
            sala.participantes[i].haAportadoRondaActual = false;
        }

        if (sala.rondaActual >= sala.numeroParticipantes) {
            sala.salaFinalizada = true;
        } else {
            sala.rondaActual++;
        }
    }

    // FUNCIONES DE CONSULTA
    function obtenerSala(string calldata hashId) external view salaExiste(hashId) returns (
        address, uint, uint8, uint8, bool, bool
    ) {
        Sala storage s = salas[hashId];
        return (s.organizador, s.montoAportar, s.numeroParticipantes, s.rondaActual, s.salaFinalizada, s.sorteoRealizado);
    }

    function obtenerParticipantes(string calldata hashId) external view salaExiste(hashId) returns (Participante[] memory) {
        return salas[hashId].participantes;
    }

    function obtenerTransacciones(string calldata hashId) external view salaExiste(hashId) returns (Transaccion[] memory) {
        return salas[hashId].transacciones;
    }

    function obtenerSalasUsuario(address usuario) external view returns (string[] memory) {
        return salasUsuario[usuario];
    }

    function obtenerPendienteRetiro(string calldata hashId, address usuario) external view salaExiste(hashId) returns (uint) {
        return salas[hashId].pendienteRetiro[usuario];
    }

    function esInvitado(string calldata hashId, address usuario) external view salaExiste(hashId) returns (bool) {
        return salas[hashId].invitados[usuario];
    }

    function obtenerTurnoUsuario(string calldata hashId, address usuario) external view salaExiste(hashId) returns (uint8) {
        uint index = _obtenerIndiceParticipante(hashId, usuario);
        return salas[hashId].participantes[index].numTurno;
    }

    // FUNCIONES AUXILIARES
    function _esParticipante(string calldata hashId, address wallet) private view returns (bool) {
        Participante[] storage participantes = salas[hashId].participantes;
        for (uint i = 0; i < participantes.length; i++) {
            if (participantes[i].wallet == wallet) return true;
        }
        return false;
    }

    function _obtenerIndiceParticipante(string calldata hashId, address wallet) private view returns (uint) {
        Participante[] storage participantes = salas[hashId].participantes;
        for (uint i = 0; i < participantes.length; i++) {
            if (participantes[i].wallet == wallet) return i;
        }
        revert NoInvitado();
    }

    function _todosHanAportado(string calldata hashId) private view returns (bool) {
        Participante[] storage participantes = salas[hashId].participantes;
        for (uint i = 0; i < participantes.length; i++) {
            if (!participantes[i].haAportadoRondaActual) return false;
        }
        return true;
    }
}