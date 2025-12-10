# 🎙️ Setup Rust-Zumble

Script de instalação automatizada do **Rust-Mumble/Zumble** (servidor de voz externo) para Ubuntu/Debian.

O Zumble é um substituto de alta performance para o servidor de voz integrado do FiveM, criado e mantido por **AvarianKnight**. Diferente do pma-voice padrão, o Zumble roda o servidor de voz em uma máquina separada, reduzindo significativamente lag de voz, áudio robotizado e outros problemas comuns — essencial para servidores com muitos jogadores.

> ⚠️ **Importante:** Isso NÃO substitui o pma-voice. Você ainda precisa ter o pma-voice rodando no seu servidor FiveM.

## 📋 Requisitos

- Ubuntu 20.04, 22.04 ou 24.04 (ou Debian 11+)
- Acesso root
- Mínimo 1GB RAM
- Conexão com internet

## 🚀 Instalação

```bash
git clone https://github.com/kvini7/setup-rust-zumble.git
cd setup-rust-zumble
chmod +x setup-rust-zumble.sh
sudo ./setup-rust-zumble.sh
```

> **Dica:** Se aparecerem prompts interativos durante a instalação, rode:
> ```bash
> export DEBIAN_FRONTEND=noninteractive
> sudo -E ./setup-rust-zumble.sh
> ```

## 🔧 O que o script faz

- ✅ Atualiza pacotes do sistema
- ✅ Instala dependências (LLVM, Clang, OpenSSL, etc.)
- ✅ Instala Rust (se necessário)
- ✅ Clona e compila o Rust-Mumble
- ✅ Gera certificados SSL auto-assinados
- ✅ Cria serviço systemd (inicia automaticamente no boot)
- ✅ Configura limites de file descriptors
- ✅ Configura regras de firewall (UFW)

## 🌐 Portas Utilizadas

| Porta | Protocolo | Descrição |
|-------|-----------|-----------|
| 55500 | TCP/UDP   | Servidor de voz |
| 8080  | TCP       | Interface HTTP (padrão) |

> **Nota:** Se a porta 8080 estiver em uso (ex: Traefik, Docker), edite o serviço para usar outra porta (ex: 8081).

## 🎮 Configuração no FiveM

### Abrir Portas no Servidor FiveM

No servidor que hospeda seu FiveM, certifique-se de abrir a porta **55500** para TCP/UDP, tanto para conexões de entrada quanto de saída.

### Configurar server.cfg

Remova TODOS os convars relacionados a voz no seu `server.cfg` e substitua por estes (e SOMENTE estes):

```cfg
# Configuração de Voz - Zumble/Rust-Mumble
setr voice_useNativeAudio true
setr voice_useSendingRangeOnly true
setr voice_defaultCycle "GRAVE"
setr voice_defaultVolume 0.3
setr voice_enableRadioAnim 1
setr voice_syncData 1
setr voice_externalAddress SEU_IP_DO_SERVIDOR_VOZ
setr voice_externalPort 55500
setr voice_hideEndpoints 1
```

> **Importante:** Substitua `SEU_IP_DO_SERVIDOR_VOZ` pelo endereço IPv4 do seu servidor de voz. NÃO adicione aspas ("") ou ('').
> 
> **Exemplo:** `setr voice_externalAddress 192.168.1.100`

## 📝 Comandos Úteis

### Gerenciamento do serviço

```bash
# Ver status
sudo systemctl status rust-mumble

# Reiniciar
sudo systemctl restart rust-mumble

# Parar
sudo systemctl stop rust-mumble

# Iniciar
sudo systemctl start rust-mumble

# Ver logs
sudo journalctl -u rust-mumble -f
```

### Verificar portas

```bash
ss -tlnp | grep -E "55500|8080"
```

## ⚙️ Configuração Avançada

### Alterar porta HTTP

Se a porta 8080 estiver ocupada:

```bash
sudo nano /etc/systemd/system/rust-mumble.service
```

Altere `--http-listen 0.0.0.0:8080` para outra porta (ex: `8081`).

Depois:

```bash
sudo systemctl daemon-reload
sudo systemctl restart rust-mumble
```

### Configurar reinício automático (Cronjob)

Configure um cronjob para reiniciar automaticamente o serviço. Isso ajuda a mitigar um problema conhecido do Zumble onde o serviço pode ficar sem resposta após exceder o limite máximo de clientes.

Para reiniciar todo dia às 19:00 (horário de Brasília):

```bash
(crontab -l 2>/dev/null; echo "0 22 * * * systemctl restart rust-mumble") | crontab -
```

> **Nota:** O servidor usa UTC. 22:00 UTC = 19:00 Brasília (UTC-3).

Para verificar o cronjob:

```bash
crontab -l
```

## 🔥 Firewall

Se o UFW estiver ativo, libere as portas:

```bash
sudo ufw allow 55500/tcp
sudo ufw allow 55500/udp
sudo ufw allow 8080/tcp  # ou 8081 se alterou
```

## 🐛 Solução de Problemas

### Erro: "Address already in use"

Outra aplicação está usando a porta. Verifique:

```bash
ss -tlnp | grep 8080
```

Altere a porta do Rust-Mumble conforme instruções acima.

### Serviço não inicia após reboot

Verifique se está habilitado:

```bash
sudo systemctl is-enabled rust-mumble
```

Se não estiver:

```bash
sudo systemctl enable rust-mumble
```

### Ver logs de erro

```bash
sudo journalctl -u rust-mumble -n 50 --no-pager
```

### Voz não funciona no FiveM

1. Verifique se o pma-voice está rodando no servidor FiveM
2. Confirme que as portas 55500 TCP/UDP estão abertas em ambos servidores
3. Verifique se o IP no `voice_externalAddress` está correto
4. Confira os logs do rust-mumble para erros

## 📁 Estrutura de Arquivos

```
/root/rust-mumble/           # Diretório do Rust-Mumble
├── target/release/          # Binário compilado
├── cert.pem                 # Certificado SSL
└── key.pem                  # Chave privada SSL

/etc/systemd/system/
└── rust-mumble.service      # Arquivo do serviço
```

## 🙏 Créditos

Este projeto é baseado no trabalho de:

- **[1 of 1 Servers](https://github.com/1-of-1-Servers/setup-rust-mumble)** - Script de setup original
- **[AvarianKnight](https://github.com/AvarianKnight/rust-mumble)** - Criador do Rust-Mumble
- **[Documentação 1of1servers](https://docs.1of1servers.com/1-of-1-game-server-guides/fivem/external-zumble-rust-mumble-server)** - Guia de instalação

Agradecimentos especiais:
- **MajorMayhem** - Setup do script
- **MonkeyWhisper** - Contribuições

## 📄 Licença

MIT License

## 🤝 Contribuições

Contribuições são bem-vindas! Abra uma issue ou pull request.