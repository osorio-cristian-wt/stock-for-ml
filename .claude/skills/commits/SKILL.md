---
name: commits
description: Revisar el estado de git y crear commits granulares (uno por cambio lógico coherente) siguiendo Conventional Commits, con body en español. Usar cuando el usuario pida "hacer commits", "commitear los cambios", o invoque /commits.
---

# /commits — commits granulares en español

Cuando se invoque esta skill:

1. Correr `git status` y `git diff` (staged y unstaged) para entender todo lo que
   cambió. Si hay archivos untracked relevantes, incluirlos en el análisis.
2. Agrupar los cambios en commits **granulares**: cada commit debe representar un
   único cambio lógico coherente (una feature, un fix, un refactor, una config).
   No mezclar features no relacionadas en un mismo commit. Si un mismo archivo
   contiene cambios de más de un concern y se pueden separar por hunks sin
   romper nada, separarlos (`git add -p` o patches parciales); si separarlos es
   inviable o de alto riesgo, agruparlo en el commit del concern dominante y
   aclararlo en el body.
3. Para cada grupo, armar el mensaje siguiendo **Conventional Commits**:
   - `tipo(scope opcional): resumen corto en español, imperativo, sin punto final`
     (tipos: feat, fix, chore, refactor, docs, test, style, build, ci, perf).
   - Línea en blanco.
   - **Body en español** explicando el *por qué* y el *qué* a alto nivel (2-5
     líneas o bullets). No es necesario repetir lo obvio del diff.
   - **NUNCA** agregar `Co-Authored-By: Claude` ni ninguna firma/atribución de
     Claude o de Anthropic en el mensaje.
4. Mostrar al usuario el plan de commits (lista corta: mensaje + archivos) antes
   de ejecutar, salvo que ya haya pedido explícitamente que se ejecute
   directamente.
5. Ejecutar con `git add <archivos del grupo>` + `git commit -m "$(cat <<'EOF' ... EOF)"`
   uno por uno, en un orden que respete dependencias (ej. migraciones antes que
   el código que las usa, modelos antes que los repos que los consumen).
6. Al terminar, correr `git log --oneline -n <cantidad>` y `git status` para
   confirmar que todo quedó commiteado y mostrarle el resultado al usuario.
7. No hacer `git push` salvo que el usuario lo pida explícitamente.
