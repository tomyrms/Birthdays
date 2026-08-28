# Birthdays

Application iOS 17 en SwiftUI pour enregistrer, organiser et ne plus manquer les anniversaires.

La version 1.7 contient un catalogue initial de 50 anniversaires, une interface recentrée sur le prochain événement, la composition photo intelligente « Memory Lens », une identité visuelle renouvelée et des widgets pour l’écran d’accueil comme pour l’écran verrouillé. Le catalogue est fusionné avec les données déjà présentes sans créer de doublons.

## Fonctionnalités

- liste chronologique avec recherche et groupes ;
- ajout, modification et suppression ;
- avatar par initiales, emoji ou photo ;
- année de naissance facultative et calcul de l’âge ;
- rappels locaux globaux ou personnalisés ;
- import depuis Contacts, Calendrier ou un fichier `.ics` ;
- export vers un fichier `.ics` ou directement vers Calendrier ;
- widgets d’écran d’accueil et d’écran verrouillé ;
- cinq fonds procéduraux complexes et animés, sélectionnables dans « … » → « Apparence » ;
- stockage local partagé avec le widget, sans compte ni backend.

L’import Facebook n’est pas inclus : l’API Meta ne donne pas accès aux anniversaires de tous les
amis. L’action « Demander une date » partage à la place un message prêt à envoyer.

## Générer et compiler

```bash
cd /Users/tomy/Desktop/Birthdays
ruby scripts/generate_project.rb
xcodebuild -project ios/Birthdays.xcodeproj -scheme Birthdays \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## IPA de développement

```bash
./scripts/build_ipa.sh
```

L’export signé dépend des appareils et capacités autorisés sur l’équipe Apple configurée.
