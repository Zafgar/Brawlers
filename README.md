# Project Arena

Värikäs, ylhäältä kuvattu paikallinen areenapeli 1–8 pelaajalle. Pelaa yksin
botteja vastaan, kaverin kanssa samassa joukkueessa tai vastakkain — samalla
ruudulla. Ensisijainen ohjain on PS5:n DualSense, ja näppäimistö + hiiri
muodostavat yhden pelaajan.

**Kaikki pelin grafiikka ja äänet luodaan koodilla** — projektissa ei ole
yhtään kuva- tai äänitiedostoa. Hahmot, kenttä, efektit ja käyttöliittymä
piirretään ajon aikana, ja ääniefektit sekä taustamusiikki syntetisoidaan
käynnistyksessä.

## Käynnistys

1. Asenna [Godot 4](https://godotengine.org/download) (4.4 tai uudempi).
2. Avaa projekti: `project.godot`.
3. Paina **F5** (tai Run-nappia).

Ei riippuvuuksia, ei asennusskriptejä.

## Ohjaimet

| Toiminto        | PS5-ohjain      | Näppäimistö + hiiri |
| --------------- | --------------- | ------------------- |
| Liikkuminen     | Vasen tatti     | WASD                |
| Tähtäys         | Oikea tatti     | Hiiri               |
| Perushyökkäys   | R2              | Hiiren vasen        |
| Kyky 1          | R1              | Hiiren oikea        |
| Kyky 2          | L1              | Q                   |
| Väistö          | Risti (X)       | Välilyönti          |
| Ultimate        | Kolmio          | E                   |
| Pudota reliikki | Ympyrä          | F                   |
| Tauko           | Options         | Esc                 |

Valikoissa liikutaan ristiohjaimella/tatilla ja hyväksytään X:llä (tai
nuolinäppäimillä ja Enterillä). Jokainen ohjain on oma pelaajansa — liity
lobbyssa painamalla X.

> Vinkki: jos DualSense ei tunnistu suoraan Windowsissa, käynnistä peli
> Steamin kautta (Steam Input) tai päivitä ohjaimen ajurit.

## Ensimmäinen versio sisältää

- **Relic Hold** -pelimuoto: pidä reliikkiä hallussa — 40 pistettä voittaa
  erän. Kantaja hidastuu eikä voi käyttää kykyjään. Tasatilanteessa
  ratkaisuhetki: seuraava pito voittaa.
- Ottelukoot **1v1–4v4**, paras kolmesta tai paras viidestä.
- **12 sankaria**: Bastion ja Boulder (tankit), Ember ja Volt (maget),
  Luma ja Maestro (tuet), Blink ja Shade (assassinit), Bramble ja Tide
  (fighterit) sekä Quill ja Scout (rangerit). Jokaisella perushyökkäys,
  kaksi kykyä, väistö, ultimate ja passiivi.
- **Kaksi kenttää**: *Geargarden* (mekaaninen puutarha: messinkirattaita,
  pensasaitoja ja pelaajia työntäviä kuljetinhihnoja) ja *Moonstone Ruins*
  (taianomaiset rauniot: hohtavat kristallit jotka reagoivat lähelläoloon,
  riimuympyrät ja ajoittain avautuvat portit sivukäytävillä).
- **Botit** kolmella vaikeustasolla. Taso muuttaa vain reaktioita,
  tarkkuutta, ennakointia ja väistämistä — ei voimaa. Botit jakavat
  joukkueen tilannekuvan: ne hakevat reliikkiä, saattavat kantajaa,
  jahtaavat vihollisen kantajaa ja vetäytyvät parantumaan.
- **MVP-järjestelmä**, joka painottaa tavoitepeliä (40 %) — myös tankki tai
  parantaja voi olla ottelun paras.
- Harjoittelutila, sankarigalleria, asetukset (äänet, tärinä) ja
  yhteinen kamera, joka seuraa koko taistelua.

Hahmot eivät vuoda verta eivätkä kuole: tyrmätty sankari poksahtaa
valoefektiksi ja palaa kentälle muutaman sekunnin päästä.

## Arkkitehtuuri

```
src/
├── main.tscn / main.gd      # Käynnistys, ruutujen juuri
├── autoload/
│   ├── game.gd              # Pelitila, asetukset, ruutujen vaihto (Game)
│   └── audio_mgr.gd         # Äänisynteesi ja toisto (AudioMgr)
├── core/
│   ├── palette.gd           # Kaikki värit yhdestä paikasta
│   ├── hero_def.gd          # Sankarien data: tilastot, kyvyt, kuvaukset
│   ├── player_profile.gd    # Pelipaikka: laite, joukkue, tilastot
│   └── device_input.gd      # Yhden laitteen syöte (ohjain tai näppis+hiiri)
├── heroes/
│   ├── hero.gd              # Kantaluokka: liike, kesto, kyvyt, tyrmäys
│   ├── hero_visual.gd       # Proseduraalinen hahmopiirto ja animaatiot
│   └── bastion.gd ... scout.gd  # Kaksitoista sankarikittiä
├── combat/
│   ├── projectile.gd        # Yleisammus (osumat, läpäisy, jälki)
│   └── zone.gd              # Aluevaikutukset (tuli, hoito, piikit, kupoli)
├── arena/
│   ├── arena.gd             # Ottelun kapellimestari: erät, pisteet, pause
│   ├── map_base.gd          # Karttojen yhteinen pohja: seinät, spawnit, apurit
│   ├── map_gear.gd          # Geargarden: mekaaninen puutarha
│   ├── map_moon.gd          # Moonstone Ruins: kristallirauniot ja portit
│   ├── relic.gd             # Reliikki ja kantologiikka
│   └── game_camera.gd       # Kaikki pelaajat rajaava kamera + tärinä
├── ai/
│   ├── bot_brain.gd         # Utility-AI, DeviceInput-yhteensopiva
│   └── team_blackboard.gd   # Joukkueen jaettu tilannekuva
├── fx/
│   ├── fx.gd                # Purskeet, renkaat, välähdykset
│   └── popup_text.gd        # Leijuvat luvut ja tekstit
└── ui/
    ├── ui_kit.gd            # Yhtenäiset napit, paneelit, tekstit
    ├── main_menu.gd, match_setup.gd, lobby.gd, hero_gallery.gd
    ├── hud.gd, player_card.gd
    ├── results.gd           # Tulosruutu ja MVP-laskenta
    └── menu_backdrop.gd     # Valikoiden animoitu tausta
```

Botti toteuttaa saman rajapinnan kuin ihmisen syöttölaite, joten sankari ei
tiedä kumpi sitä ohjaa. Uusi sankari lisätään kirjoittamalla `hero_def.gd`-
dataan rivi ja perimällä `Hero`-luokka (~100 riviä).

## Miksi 2D?

Speksi harkitsi 2D:tä ja 3D:tä. Valinta on tietoisesti **2D + 2.5D-vaikutelma**:

- 8 pelaajaa yhdellä jaetulla kameralla vaatii täydellistä luettavuutta.
- 60 FPS toteutuu heikommallakin koneella, myös 4v4-tilanteissa.
- Koodilla generoitu vektorigrafiikka näyttää 2D:nä viimeistellyltä;
  varjot, hyppyvaikutelma ja squash & stretch antavat syvyyden tunnun.

## Jatkosuunnitelma (speksin mukaan)

- Loput pelimuodot: Shard Rush, Zone Shift, Core Clash
- Kolmas kenttä: Splashport
- Sankarimäärän kasvatus kahdestatoista kahteenkymmeneen
- Verkkopeli / Steam Remote Play -tuki
