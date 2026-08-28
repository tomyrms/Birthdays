# Birthdays — conventions

- Communication et documentation en français ; identifiants de code en anglais.
- SwiftUI, iOS 17 minimum, iPhone uniquement pour la première version.
- L’interface reste sobre : une couleur d’accent, rayons contenus, aucun dégradé décoratif.
- Les données utilisateur restent locales ; un instantané sans photo est partagé avec le widget via le trousseau iOS.
- Les permissions Contacts, Calendrier, Photos et Notifications sont demandées au moment utile.
- L’app doit rester utilisable sans compte, sans backend et sans connexion réseau.
- Exécuter les tests de domaine et un build iPhone générique sans simulateur avant livraison.
- Ne jamais committer de certificat, profil de provisioning, archive ou IPA.
