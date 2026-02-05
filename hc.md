Homebrew Cask 배포 체크리스트                                                                                    
                                                                                                                   
  ---                                                                                                              
  Phase 1: 사전 준비                                                                                               
                                                                                                                   
  ☐ 1.1 Apple Developer 계정 확인                                                                                  
                                                                                                                   
  # 이미 있는지 확인 (Xcode에서)                                                                                   
  # Xcode → Settings → Accounts                                                                                    
  - 연간 $99 (₩129,000)                                                                                            
  - https://developer.apple.com/programs/                                                                          
                                                                                                                   
  ☐ 1.2 Developer ID 인증서 확인                                                                                   
                                                                                                                   
  # 터미널에서 확인                                                                                                
  security find-identity -v -p codesigning | grep "Developer ID Application"                                       
  없으면: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application                         
                                                                                                                   
  ☐ 1.3 App-Specific Password 생성                                                                                 
                                                                                                                   
  1. https://appleid.apple.com 접속                                                                                
  2. 로그인 → 앱 암호 → + 생성                                                                                     
  3. 이름: notarytool 입력                                                                                         
  4. 생성된 암호 저장 (예: xxxx-xxxx-xxxx-xxxx)                                                                    
                                                                                                                   
  ---                                                                                                              
  Phase 2: 앱 빌드 및 서명                                                                                         
                                                                                                                   
  ☐ 2.1 Release 빌드 설정 확인                                                                                     
                                                                                                                   
  # Xcode에서 Scheme을 Release로 변경                                                                              
  # Product → Scheme → Edit Scheme → Run → Build Configuration → Release                                           
                                                                                                                   
  ☐ 2.2 Archive 생성                                                                                               
                                                                                                                   
  Xcode → Product → Archive                                                                                        
  (빌드 완료까지 대기)                                                                                             
                                                                                                                   
  ☐ 2.3 Export (Developer ID)                                                                                      
                                                                                                                   
  1. Archive 완료 후 Organizer 창 열림                                                                             
  2. Distribute App 클릭                                                                                           
  3. Direct Distribution 선택                                                                                      
  4. Next → Export 클릭                                                                                            
  5. 저장 위치 선택 (예: ~/Desktop/AgentHub-export)                                                                
                                                                                                                   
  ---                                                                                                              
  Phase 3: 공증 (Notarization)                                                                                     
                                                                                                                   
  ☐ 3.1 Keychain에 인증 정보 저장                                                                                  
                                                                                                                   
  xcrun notarytool store-credentials "AgentHub-notary" \                                                           
    --apple-id "YOUR_APPLE_ID@email.com" \                                                                         
    --team-id "YOUR_TEAM_ID" \                                                                                     
    --password "xxxx-xxxx-xxxx-xxxx"                                                                               
  - YOUR_APPLE_ID: Apple 계정 이메일                                                                               
  - YOUR_TEAM_ID: 개발자 팀 ID (Xcode → Settings → Accounts에서 확인)                                              
  - 마지막은 Phase 1.3에서 생성한 앱 암호                                                                          
                                                                                                                   
  ☐ 3.2 DMG 생성                                                                                                   
                                                                                                                   
  # Export된 앱 위치로 이동                                                                                        
  cd ~/Desktop/AgentHub-export                                                                                     
                                                                                                                   
  # DMG 생성                                                                                                       
  hdiutil create -volname "AgentHub" \                                                                             
    -srcfolder AgentHub.app \                                                                                      
    -ov -format UDZO \                                                                                             
    ~/Desktop/AgentHub-1.0.0.dmg                                                                                   
                                                                                                                   
  ☐ 3.3 공증 제출                                                                                                  
                                                                                                                   
  xcrun notarytool submit ~/Desktop/AgentHub-1.0.0.dmg \                                                           
    --keychain-profile "AgentHub-notary" \                                                                         
    --wait                                                                                                         
  (5-15분 소요, "Accepted" 나올 때까지 대기)                                                                       
                                                                                                                   
  ☐ 3.4 Staple (공증 정보 첨부)                                                                                    
                                                                                                                   
  xcrun stapler staple ~/Desktop/AgentHub-1.0.0.dmg                                                                
                                                                                                                   
  ☐ 3.5 공증 확인                                                                                                  
                                                                                                                   
  spctl --assess -vv --type open ~/Desktop/AgentHub-1.0.0.dmg                                                      
  # "accepted" 또는 "source=Notarized Developer ID" 확인                                                           
                                                                                                                   
  ---                                                                                                              
  Phase 4: GitHub Release 생성                                                                                     
                                                                                                                   
  ☐ 4.1 버전 태그 생성                                                                                             
                                                                                                                   
  cd /Users/intmain/workspace/agenthub/AgentHubMac                                                                 
  git tag v1.0.0                                                                                                   
  git push origin v1.0.0                                                                                           
                                                                                                                   
  ☐ 4.2 Release 생성 및 DMG 업로드                                                                                 
                                                                                                                   
  gh release create v1.0.0 ~/Desktop/AgentHub-1.0.0.dmg \                                                          
    --title "AgentHub 1.0.0" \                                                                                     
    --notes "AI 코딩 에이전트 통합 모니터링 앱                                                                     
                                                                                                                   
  ## 기능                                                                                                          
  - Claude Code, Codex CLI, Gemini CLI 세션 모니터링                                                               
  - 토큰 사용량 및 비용 추적                                                                                       
  - 메뉴바 앱 + 대시보드                                                                                           
  - macOS 위젯 지원"                                                                                               
                                                                                                                   
  ☐ 4.3 Release URL 확인                                                                                           
                                                                                                                   
  gh release view v1.0.0 --json url                                                                                
  # URL 복사해두기                                                                                                 
                                                                                                                   
  ---                                                                                                              
  Phase 5: Homebrew Tap 생성                                                                                       
                                                                                                                   
  ☐ 5.1 SHA256 해시 계산                                                                                           
                                                                                                                   
  shasum -a 256 ~/Desktop/AgentHub-1.0.0.dmg                                                                       
  # 결과 복사 (예: a1b2c3d4e5f6...)                                                                                
                                                                                                                   
  ☐ 5.2 Tap 저장소 생성                                                                                            
                                                                                                                   
  cd ~/workspace                                                                                                   
  mkdir homebrew-agenthub                                                                                          
  cd homebrew-agenthub                                                                                             
  git init                                                                                                         
  mkdir Casks                                                                                                      
                                                                                                                   
  ☐ 5.3 Cask 파일 작성                                                                                             
                                                                                                                   
  cat > Casks/agenthub.rb << 'EOF'                                                                                 
  cask "agenthub" do                                                                                               
    version "1.0.0"                                                                                                
    sha256 "여기에_SHA256_해시_붙여넣기"                                                                           
                                                                                                                   
    url "https://github.com/YOUR_USERNAME/AgentHubMac/releases/download/v#{version}/AgentHub-#{version}.dmg"       
    name "AgentHub"                                                                                                
    desc "AI coding agent monitoring dashboard for Claude, Codex, Gemini"                                          
    homepage "https://github.com/YOUR_USERNAME/AgentHubMac"                                                        
                                                                                                                   
    depends_on macos: ">= :ventura"                                                                                
                                                                                                                   
    app "AgentHub.app"                                                                                             
                                                                                                                   
    zap trash: [                                                                                                   
      "~/Library/Application Support/com.agenthub.app",                                                            
      "~/Library/Preferences/com.agenthub.app.plist",                                                              
      "~/Library/Caches/com.agenthub.app",                                                                         
    ]                                                                                                              
  end                                                                                                              
  EOF                                                                                                              
  YOUR_USERNAME과 sha256 값 수정 필수!                                                                             
                                                                                                                   
  ☐ 5.4 GitHub에 Tap 저장소 Push                                                                                   
                                                                                                                   
  cd ~/workspace/homebrew-agenthub                                                                                 
  git add .                                                                                                        
  git commit -m "Add agenthub cask"                                                                                
  gh repo create homebrew-agenthub --public --source=. --push                                                      
                                                                                                                   
  ---                                                                                                              
  Phase 6: 테스트                                                                                                  
                                                                                                                   
  ☐ 6.1 Tap 추가 및 설치 테스트                                                                                    
                                                                                                                   
  # 기존 앱 삭제                                                                                                   
  rm -rf /Applications/AgentHub.app                                                                                
                                                                                                                   
  # Tap 추가                                                                                                       
  brew tap YOUR_USERNAME/agenthub                                                                                  
                                                                                                                   
  # 설치                                                                                                           
  brew install --cask agenthub                                                                                     
                                                                                                                   
  # 앱 실행 확인                                                                                                   
  open /Applications/AgentHub.app                                                                                  
                                                                                                                   
  ☐ 6.2 제거 테스트                                                                                                
                                                                                                                   
  brew uninstall --cask agenthub                                                                                   
                                                                                                                   
  ---                                                                                                              
  완료 후 사용자 안내                                                                                              
                                                                                                                   
  README에 추가:                                                                                                   
  ## 설치                                                                                                          
                                                                                                                   
  ### Homebrew (권장)                                                                                              
  ```bash                                                                                                          
  brew tap YOUR_USERNAME/agenthub                                                                                  
  brew install --cask agenthub                                                                                     
                                                                                                                   
  수동 설치                                                                                                        
                                                                                                                   
  https://github.com/YOUR_USERNAME/AgentHubMac/releases에서 DMG 다운로드                                           
                                                                                                                   
  ---                                                                                                              
                                                                                                                   
  ### 요약 체크리스트                                                                                              
                                                                                                                   
  | Phase | 단계 | 완료 |                                                                                          
  |-------|------|------|                                                                                          
  | 1 | Apple Developer 계정 | ☐ |                                                                                 
  | 1 | Developer ID 인증서 | ☐ |                                                                                  
  | 1 | App-Specific Password | ☐ |                                                                                
  | 2 | Archive 생성 | ☐ |                                                                                         
  | 2 | Export (Developer ID) | ☐ |                                                                                
  | 3 | Keychain 인증 저장 | ☐ |                                                                                   
  | 3 | DMG 생성 | ☐ |                                                                                             
  | 3 | 공증 제출 | ☐ |                                                                                             
  | 3 | Staple | ☐ |                                                                                               
  | 4 | Git 태그 | ☐ |                                                                                             
  | 4 | GitHub Release | ☐ |                                                                                       
  | 5 | SHA256 계산 | ☐ |                                                                                          
  | 5 | Cask 파일 작성 | ☐ |                                                                                       
  | 5 | Tap 저장소 Push | ☐ |                                                                                      
  | 6 | 설치 테스트 | ☐ |      