# Como Verificar e Criar Índices do Firebase

## 1. Verificar Logs no Terminal

Quando você rodar o app, procure por mensagens de erro como:

```
[cloud_firestore/failed-precondition] The query requires an index.
You can create it here: https://console.firebase.google.com/...
```

## 2. Queries que Podem Precisar de Índice

Baseado no código atual, estas são as queries compostas que podem precisar de índices:

### Query 1: Chats com ordenação
```dart
chatsCollection.snapshots() // sem filtro complexo
```
**Status:** ✅ Não precisa de índice composto

### Query 2: Groups com ordenação
```dart
groupsCollection.snapshots() // sem filtro complexo
```
**Status:** ✅ Não precisa de índice composto

### Query 3: Usuários não-admin
```dart
usersCollection.where('isAdmin', isEqualTo: false).get()
```
**Status:** ✅ Não precisa de índice composto (apenas um where)

### Query 4: Mensagens do grupo ordenadas
```dart
groupsCollection.doc(groupId).collection('messages').orderBy('timestamp', descending: true)
```
**Status:** ✅ Não precisa de índice composto (subcoleção + orderBy simples)

### Query 5: CollectionGroup de feedbacks
```dart
FirebaseFirestore.instance
    .collectionGroup('feedbacks')
    .orderBy('timestamp', descending: true)
    .snapshots()
```
**Status:** ⚠️ PODE PRECISAR DE ÍNDICE (collectionGroup + orderBy)

## 3. Como Criar Índice Manualmente

Se você ver erro de índice no console:

1. **Copie o link** fornecido na mensagem de erro
2. **Cole no navegador** - ele abrirá o Firebase Console
3. **Clique em "Create Index"**
4. **Aguarde** 1-3 minutos para o índice ser criado
5. **Tente novamente** no app

## 4. Índices Recomendados para Criar Preventivamente

### Índice para Feedbacks (collectionGroup)

**Coleção:** `feedbacks` (Collection Group)

**Campos indexados:**
- `timestamp` - Descending
- `__name__` - Descending (documento ID)

**Como criar:**

1. Acesse: [Firebase Console](https://console.firebase.google.com/)
2. Selecione seu projeto
3. Vá em **Firestore Database** → **Indexes**
4. Clique em **Create Index**
5. Preencha:
   - Collection ID: `feedbacks`
   - Query scope: **Collection group**
   - Fields to index:
     - Field: `timestamp`, Order: `Descending`
     - Field: `__name__`, Order: `Descending`
6. Clique em **Create**

## 5. Teste e Monitore

Execute o app e monitore o console do Flutter para qualquer mensagem de erro relacionada a índices.

Se aparecer algum erro, copie o link fornecido e me envie para que eu possa ajudar!

## 6. Comandos para Monitorar

Execute o app com logs detalhados:

```powershell
flutter run --verbose
```

Ou apenas observe o console durante o uso normal:

```powershell
flutter run
```

Procure por linhas contendo:
- `failed-precondition`
- `requires an index`
- `You can create it here`
