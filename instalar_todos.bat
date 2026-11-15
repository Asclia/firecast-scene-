@echo off
rem Compila e instala todos os plugins da Scene Suite no Firecast aberto.
rem Para instalar apenas alguns, remova as pastas indesejadas de "plugins" antes.
setlocal
for /d %%D in ("%~dp0plugins\SceneSuite_*") do (
  echo === %%~nxD ===
  pushd "%%D"
  if not exist sdk call rdk p
  call rdk i
  popd
)
pause
