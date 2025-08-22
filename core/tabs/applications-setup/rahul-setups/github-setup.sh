#!/usr/bin/env bash
set -e

declare -A ACCOUNTS=(
  [rahuljangirworks]="aarjaycreation@gmail.com"
  [rahuljangirwork]="rahuljangir.work@gmail.com"
  [rahuljangirgms]="rahul.jangir@getmysolutions.in"
)

SSH_DIR="$HOME/.ssh"

mkdir -p "$SSH_DIR"

echo "== Generating SSH keys =="
for acct in "${!ACCOUNTS[@]}"; do
  email="${ACCOUNTS[$acct]}"
  keyfile="$SSH_DIR/${acct}_ed25519"

  if [[ -f "$keyfile" ]]; then
    echo "→ Skipping $keyfile (already exists)"
  else
    ssh-keygen -t ed25519 -C "$email" -f "$keyfile" -N ""
    echo "→ Created key for $acct ($email)"
  fi
done

echo "== Configuring SSH =="
cat > "$SSH_DIR/config" << EOF
# GitHub multi-account config
EOF

for acct in "${!ACCOUNTS[@]}"; do
  echo "Host github-$acct
  HostName github.com
  User git
  IdentityFile $SSH_DIR/${acct}_ed25519
  IdentitiesOnly yes
" >> "$SSH_DIR/config"
done

chmod 600 "$SSH_DIR/config"
echo "→ SSH config updated"

echo "== Loading keys into ssh-agent =="
eval "$(ssh-agent -s)"
for acct in "${!ACCOUNTS[@]}"; do
  ssh-add "$SSH_DIR/${acct}_ed25519"
done

echo -e "\n✅ Done! Next steps:"
echo "1. Copy each public key:"
for acct in "${!ACCOUNTS[@]}"; do
  echo "   - ~/.ssh/${acct}_ed25519.pub → GitHub account: $acct"
done
echo "2. Add keys via GitHub → Settings → SSH and GPG keys."
echo "3. Test with:"
for acct in "${!ACCOUNTS[@]}"; do
  echo "   ssh -T git@github-$acct"
done
echo "4. Clone using alias, e.g.:"
echo "   git clone git@github-rahuljangirworks:USERNAME/REPO.git"

exit 0
