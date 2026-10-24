#!/usr/bin/env bash
# ==============================================================================
# Nexo Desktop - Instalador e Gerenciador CLI para Linux
# Suporta: curl -fsSL ... | bash, instalação via terminal, atualização e remoção.
# ==============================================================================

set -e

# Configurações do repositório
GITHUB_REPO="RichardtJustke/nexo-desktop"
APP_NAME="Nexo"
BINARY_NAME="nexo"

# Cores e estilos
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✔${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✖${NC} $1"; }

banner() {
  cat << "EOF"
  _  _ _____  _____ 
 | \| | __\ \/ / _ \
 | .` | _| >  < (_) |
 |_|\_|___/_/\_\___/ 
                     
EOF
  echo -e "${BOLD}Nexo Desktop Installer & CLI Manager${NC}\n"
}

# Ajuda
show_help() {
  banner
  echo -e "Uso: $0 [COMANDO | OPÇÕES]"
  echo ""
  echo "Comandos:"
  echo "  install            Instala a versão mais recente do Nexo (padrão)"
  echo "  update             Verifica e atualiza para a versão mais recente"
  echo "  uninstall          Remove a instalação do Nexo e seus atalhos"
  echo "  version, -v        Mostra a versão instalada e a versão remota"
  echo "  help, -h           Mostra esta mensagem de ajuda"
  echo ""
  echo "Opções:"
  echo "  --format [deb|appimage]   Força o tipo de pacote a ser instalado"
  echo "  --dest <caminho>          Diretório de destino (padrão: ~/.local/bin)"
  echo "  --system                  Instala no sistema (/usr/local/bin, requer sudo)"
  echo ""
  exit 0
}

# Detecta Arquitetura
detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      log_error "Arquitetura não suportada: $arch"
      exit 1
      ;;
  esac
}

# Obter última versão no GitHub
get_latest_release() {
  local release_json
  release_json=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || true)
  local tag
  tag=$(echo "$release_json" | grep -oP '"tag_name":\s*"\K[^"]+' || true)
  if [ -z "$tag" ]; then
    # Fallback para tags
    tag=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/tags" | grep -oP '"name":\s*"\K[^"]+' | head -n 1 || true)
  fi
  echo "$tag"
}

# Endereço de download de um arquivo da release, pelo final do nome (ex.: "_amd64.deb")
asset_url() {
  local tag="$1"
  local suffix="$2"
  curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${tag}" \
    | grep -oP '"browser_download_url":\s*"\K[^"]+' \
    | grep -F -- "$suffix" | head -n 1
}

# Instalação do pacote .deb
install_deb() {
  local tag="$1"
  local arch="$2"
  local tmp_deb="/tmp/nexo_${tag}_${arch}.deb"
  local deb_url
  deb_url=$(asset_url "$tag" "_${arch}.deb")

  log_info "Baixando pacote Debian de: ${deb_url:-(não encontrado)}"
  if [ -z "$deb_url" ] || ! curl -fsSL -o "$tmp_deb" "$deb_url"; then
    log_warn "Download do .deb falhou. Tentando modo AppImage..."
    install_appimage "$tag" "$arch" "${HOME}/.local/bin"
    return
  fi

  log_info "Instalando pacote com dpkg/apt..."
  if [ "$(id -u)" -eq 0 ]; then
    dpkg -i "$tmp_deb" || apt-get install -f -y
  else
    sudo dpkg -i "$tmp_deb" || sudo apt-get install -f -y
  fi
  rm -f "$tmp_deb"
  log_success "Nexo instalado com sucesso via pacote Debian!"
}

# Instalação do AppImage
install_appimage() {
  local tag="$1"
  local arch="$2"
  local target_dir="$3"
  local appimage_arch="x86_64"
  [ "$arch" = "arm64" ] && appimage_arch="aarch64"

  local bin_path="${target_dir}/${BINARY_NAME}"
  local appimage_url
  # O Tauri nomeia o AppImage com amd64/aarch64 (ex.: Nexo_0.1.0_amd64.AppImage); x86_64 fica de reserva
  appimage_url=$(asset_url "$tag" "_${arch}.AppImage")
  [ -z "$appimage_url" ] && appimage_url=$(asset_url "$tag" "_${appimage_arch}.AppImage")

  mkdir -p "$target_dir"
  log_info "Baixando Nexo AppImage de: ${appimage_url:-(não encontrado)}"
  if [ -z "$appimage_url" ] || ! curl -fsSL -o "$bin_path" "$appimage_url"; then
    log_error "Não foi possível baixar o Nexo $tag para ${appimage_arch}."
    exit 1
  fi

  chmod +x "$bin_path"
  log_success "Binário salvo e tornado executável em: $bin_path"

  # Criar atalho no ambiente Desktop
  install_desktop_entry "$bin_path" "$target_dir"
}

# Criar atalho .desktop e ícone
install_desktop_entry() {
  local bin_path="$1"
  local target_dir="$2"
  local apps_dir="${HOME}/.local/share/applications"
  local icons_dir="${HOME}/.local/share/icons/hicolor/512x512/apps"

  if [ "$target_dir" = "/usr/local/bin" ] || [ "$(id -u)" -eq 0 ]; then
    apps_dir="/usr/share/applications"
    icons_dir="/usr/share/icons/hicolor/512x512/apps"
  fi

  mkdir -p "$apps_dir" "$icons_dir"

  # Baixar ícone oficial em alta resolução
  local icon_dest="${icons_dir}/nexo.png"
  curl -fsSL -o "$icon_dest" "https://raw.githubusercontent.com/${GITHUB_REPO}/main/assets/icon.png" 2>/dev/null || true

  # Gerar arquivo .desktop
  cat << EOF > "${apps_dir}/nexo.desktop"
[Desktop Entry]
Name=Nexo
GenericName=Produtividade & Gestão
Comment=Sistema Integrado de Produtividade, Finanças e Hábitos
Exec=${bin_path} %U
Icon=nexo
Terminal=false
Type=Application
Categories=Office;Utility;ProjectManagement;
StartupWMClass=Nexo
EOF

  chmod +x "${apps_dir}/nexo.desktop"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$apps_dir" 2>/dev/null || true
  fi

  log_success "Atalho na área de trabalho e menu de aplicativos criado com sucesso!"
}

# Desinstalação
uninstall() {
  banner
  log_info "Removendo Nexo..."

  # Remover de diretórios de usuário
  rm -f "${HOME}/.local/bin/${BINARY_NAME}"
  rm -f "${HOME}/.local/share/applications/nexo.desktop"
  rm -f "${HOME}/.local/share/icons/hicolor/512x512/apps/nexo.png"

  # Se tiver dpkg, remove pacote deb caso instalado
  if command -v dpkg >/dev/null 2>&1; then
    if dpkg -s nexo >/dev/null 2>&1; then
      log_info "Removendo pacote Debian 'nexo'..."
      sudo apt-get remove -y nexo || sudo dpkg -r nexo
    fi
  fi

  # Remover de /usr/local/bin se existir
  if [ -f "/usr/local/bin/${BINARY_NAME}" ]; then
    sudo rm -f "/usr/local/bin/${BINARY_NAME}" "/usr/share/applications/nexo.desktop" 2>/dev/null || true
  fi

  log_success "Nexo foi completamente desinstalado."
  exit 0
}

# Verificação de versão
check_version() {
  local installed="Não instalado"
  if command -v nexo >/dev/null 2>&1; then
    installed=$(nexo --version 2>/dev/null || echo "Instalado (versão não informada)")
  fi
  local latest
  latest=$(get_latest_release)

  echo -e "Versão instalada: ${BOLD}${installed}${NC}"
  echo -e "Última versão disponível: ${BOLD}${latest:-Desconhecida}${NC}"
  exit 0
}

# Fluxo principal de instalação
main() {
  local action="install"
  local format="auto"
  local dest="${HOME}/.local/bin"

  while [ $# -gt 0 ]; do
    case "$1" in
      install|update) action="install" ;;
      uninstall) action="uninstall" ;;
      version|-v|--version) action="version" ;;
      help|-h|--help) show_help ;;
      --deb) format="deb" ;;
      --appimage) format="appimage" ;;
      --format)
        shift
        format="$1"
        ;;
      --dest)
        shift
        dest="$1"
        ;;
      --system)
        dest="/usr/local/bin"
        ;;
      *)
        log_error "Argumento desconhecido: $1"
        show_help
        ;;
    esac
    shift
  done

  if [ "$action" = "uninstall" ]; then
    uninstall
  fi

  if [ "$action" = "version" ]; then
    check_version
  fi

  banner
  local arch
  arch=$(detect_arch)
  log_info "Detectada arquitetura: ${BOLD}${arch}${NC}"

  log_info "Buscando informações da versão mais recente..."
  local tag
  tag=$(get_latest_release)
  if [ -z "$tag" ]; then
    tag="v0.1.0"
    log_warn "Não foi possível consultar a API do GitHub. Usando tag fallback: ${tag}"
  else
    log_info "Versão mais recente identificada: ${BOLD}${tag}${NC}"
  fi

  # Decisão do formato
  if [ "$format" = "auto" ]; then
    if command -v apt-get >/dev/null 2>&1 && [ -f /etc/debian_version ]; then
      format="deb"
    else
      format="appimage"
    fi
  fi

  if [ "$format" = "deb" ]; then
    install_deb "$tag" "$arch"
  else
    install_appimage "$tag" "$arch" "$dest"
    # Sugere adicionar ao PATH se não estiver
    if [[ ":$PATH:" != *":$dest:"* ]]; then
      echo ""
      log_warn "O diretório $dest não está no seu PATH."
      echo -e "Adicione a seguinte linha ao seu ~/.bashrc ou ~/.zshrc:\n"
      echo -e "    ${BOLD}export PATH=\"\$PATH:${dest}\"${NC}\n"
    fi
  fi

  echo ""
  log_success "Pronto! Você pode abrir o Nexo pelo menu de aplicativos ou digitando '${BINARY_NAME}' no terminal."
}

main "$@"
