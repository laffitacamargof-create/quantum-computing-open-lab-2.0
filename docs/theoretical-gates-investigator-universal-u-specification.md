# QuOLab Nexus — Especificación funcional y técnica
## Puertas teóricas, Quantum Circuit Investigator y puerta universal U

**Módulos:** Quantum Open Lab y Quantum Notebook  
**Idioma de interfaz:** inglés en todos los títulos, menús, controles, etiquetas, ayudas y mensajes.  
**Estado:** especificación para implementación; no implica que las funcionalidades estén ya desarrolladas.

## 1. Visión general

La ampliación incorpora tres capacidades: (1) creación y administración de puertas cuánticas teóricas compuestas por puertas básicas del ecosistema; (2) un módulo independiente que permita observar la evolución ideal de los circuitos paso a paso, con esferas de Bloch y cálculos matriciales; y (3) una puerta universal teórica U que busque una secuencia de puertas básicas para alcanzar un objetivo especificado.

Quantum Open Lab será el entorno principal para crear y administrar puertas teóricas, configurar U y abrir el Investigador. Quantum Notebook reconocerá las definiciones compartidas, las representará en sus circuitos visuales y las ejecutará con la misma semántica.

## 2. Creación de puertas teóricas

### 2.1 Ubicación

Añadir **Theoretical Gates** al final del panel de puertas de Quantum Open Lab, justo antes de los instrumentos de medición. Mostrar **Create New Gate**, las dos últimas puertas creadas y un botón cuadrado sin relleno con **+** para abrir el inventario completo.

### 2.2 Ventana de creación

Al seleccionar **Create New Gate**, abrir una ventana amplia, pero no maximizada, manteniendo visible el panel de puertas básicas. En la parte superior incluir **Gate Name**. El usuario podrá alternar entre dos métodos de construcción mediante un control de cambio de modo.

### 2.3 Método visual — Visual Circuit Editor

- Mostrar un circuito visual en miniatura y los cables de los qubits necesarios.
- Mantener accesible el panel de puertas básicas del ecosistema.
- Permitir arrastrar y soltar puertas sobre los cables para construir la secuencia.
- Admitir operaciones de uno o varios qubits, incluidas puertas que actúan sobre qubits entrelazados.
- Permitir revisar, reordenar y retirar operaciones antes de guardar.

### 2.4 Método Python — Python Editor

Permitir cambiar al editor Python y programar directamente la definición. Ambos métodos deberán producir una definición ejecutable equivalente y validada. Cambiar de modo no deberá borrar el trabajo no guardado; deberá conservarlo o advertir claramente si una conversión no puede representarse.

### 2.5 Identidad visual y nomenclatura

Todas las puertas teóricas serán cuadrados blancos con la primera letra del nombre en mayúscula. Si varias puertas comparten inicial, se añadirá un número correlativo empezando por 2: F2, F3, F4, etc. Los identificadores serán únicos y estables; renombrar no deberá producir colisiones ni cambiar referencias silenciosamente. Las puertas teóricas se distinguirán de las básicas y de U.

### 2.6 Función Python ejecutable

Cada puerta guardada se expondrá como función reutilizable que invoque la secuencia de operaciones básicas que la define. Ejemplo:

```python
qc.F(1, 2)
```

Convención: `qc.<GateIdentifier><QubitArguments>`. Los argumentos dependerán de la aridad. Una puerta de dos qubits recibirá ambos índices o referencias. La función ejecutará operaciones reales, no solo dibujará un símbolo. Validar número de qubits, índices, orden de aplicación y compatibilidad. Evitar dependencias circulares y recursión no controlada.

## 3. Inventario de puertas teóricas

### 3.1 Ventana

El botón **+** abrirá **Theoretical Gate Inventory**, una ventana grande pero no de pantalla completa, permitiendo consultar puertas sin perder de vista el panel general de puertas básicas.

### 3.2 Acciones

- Seleccionar una puerta para utilizarla.
- Arrastrarla al circuito o panel de puertas.
- Asignarla a la sección general de puertas.
- Consultar su circuito y definición interna.
- Editarla o eliminarla.
- Crear una nueva versión basada en otra, conservando la original y asignando otro nombre.

### 3.3 Menú contextual

El clic derecho sobre una puerta mostrará su circuito interno, con la combinación de puertas básicas y los cables sobre los que actúan. Desde esa ventana estarán disponibles editar, eliminar y crear versión. En pantallas táctiles, mantener presionada la puerta ofrecerá el mismo menú.

### 3.4 Persistencia

Guardar localmente las definiciones en Quantum Open Lab y conservarlas tras cerrar y reabrir la aplicación mientras los datos locales sigan disponibles. Guardar definición lógica y metadatos: identificador, nombre, inicial, número de qubits, fechas y versión del esquema. Prever importación, exportación y recuperación. Persistencia local no equivale a copia remota.

## 4. Integración con Quantum Notebook

Quantum Notebook consultará el registro compartido y reconocerá nombres, símbolos, identificadores y número de qubits. En los circuitos de las celdas, las puertas teóricas aparecerán como cuadrados blancos con la inicial correspondiente.

Deberá reconocer las puertas disponibles, representarlas con el mismo identificador, resolver y ejecutar su definición, reflejar actualizaciones sin copias divergentes y mostrar errores claros ante definiciones eliminadas, dañadas o incompatibles. Ambos módulos utilizarán un registro o formato común.

## 5. Matrices de las puertas

El menú contextual de cada puerta básica permitirá consultar la matriz de su operador lineal. Para una puerta teórica se calculará la matriz resultante de la composición, respetando el orden de aplicación. Si primero se aplica U1, después U2 y finalmente U3:

```
|ψ′⟩ = U3 U2 U1 |ψ⟩
```

La interfaz mostrará explícitamente el orden y respetará la convención de endianess y orden de qubits del simulador. Las puertas multiqubit usarán matrices del espacio de Hilbert conjunto. Las operaciones sobre subconjuntos se expandirán correctamente al espacio total. La matriz mostrada, la función Python y la ejecución deberán describir exactamente la misma operación.

## 6. Quantum Circuit Investigator

Crear un módulo independiente **Quantum Circuit Investigator**, accesible desde Quantum Open Lab y Quantum Notebook. Cada celda con circuito visual podrá invocarlo. Permitirá comprender qué sucede con los qubits al atravesar cada puerta. Inicialmente funcionará en condiciones ideales, sin ruido.

### 6.1 Vista del circuito

La parte superior mostrará el circuito ampliado, con cables de qubits y una esfera de Bloch asociada a cada qubit. Será similar a los circuitos de Notebook, pero ocupará más espacio. Reconocerá puertas básicas y teóricas.

### 6.2 Reproducción por etapas

La ejecución se organizará en pasos sincronizados. En cada paso se aplicarán las operaciones siguientes de los distintos cables, respetando dependencias y puertas multiqubit. Controles:

- **Previous Step:** regresar.
- **Next Step:** avanzar.
- **Play:** reproducir automáticamente.
- **Pause:** detener.
- **Speed Control:** cambiar velocidad.

Avanzar y retroceder deberá mantener un estado coherente. Se podrán usar snapshots o reconstrucción determinista desde el inicio.

### 6.3 Exploración individual

Seleccionar una esfera de Bloch abrirá una vista ampliada con zoom y rotación. Mostrar estado antes y después, amplitudes y coordenadas relevantes. Distinguir el estado global del sistema del estado reducido de cada qubit. Si hay entrelazamiento, el estado reducido puede ser mixto; la esfera deberá derivarse de la matriz de densidad reducida y su vector de Bloch, no representar incorrectamente un estado puro independiente.

### 6.4 Panel matemático

Debajo del circuito habrá un panel sincronizado que mostrará vector inicial, matriz del operador, multiplicación, vector resultante, amplitudes y probabilidades. Para operaciones multiqubit explicará productos tensoriales y evolución conjunta.

```
|ψ1⟩ = U1 |ψ0⟩
|ψ2⟩ = U2 |ψ1⟩
|ψf⟩ = Un ··· U2 U1 |ψ0⟩
```

Los cálculos serán inspeccionables paso a paso. Para sistemas grandes se permitirán vistas parciales y expansión bajo demanda sin alterar el cálculo.

## 7. Puerta universal teórica U

### 7.1 Concepto

Añadir **Universal Theoretical Gate U**, representada por un cuadrado negro con una U blanca. Será una herramienta de síntesis: el usuario define un objetivo y el sistema busca una secuencia de puertas básicas que lo produzca dentro de las restricciones. No es una puerta física adicional capaz de realizar cualquier transformación arbitraria.

### 7.2 Configuración

Al hacer clic izquierdo, abrir la ventana de configuración con dos métodos:

- **Bloch Sphere Configuration:** definir visualmente estados objetivo mediante esferas de Bloch.
- **Probability Configuration:** definir probabilidades deseadas de los resultados de medición.

Para sistemas multiqubit se permitirán distribuciones conjuntas. Para especificar un estado completo deberán considerarse amplitudes y fases relativas; las probabilidades solas no determinan toda la información del estado.

### 7.3 Motor interno de síntesis

La síntesis funcionará con algoritmos matemáticos internos, sin depender obligatoriamente de una API de IA. El motor interpretará el objetivo, generará secuencias candidatas, simulará su acción, comparará resultados y seleccionará soluciones que satisfagan una tolerancia.

- Validar dimensiones, qubits y tipo de objetivo.
- Generar combinaciones permitidas.
- Limitar profundidad, tiempo y recursos.
- Aplicar poda, deduplicación y optimización.
- Comparar mediante una métrica adecuada.
- Mostrar secuencia, matriz y circuito.
- Permitir insertar la solución en el circuito.

Si no encuentra solución bajo las restricciones, deberá indicarlo. Las soluciones aproximadas se etiquetarán como tales e incluirán error o fidelidad; nunca se presentarán como exactas.

### 7.4 Historial

Guardar localmente objetivos, parámetros y soluciones. Permitir consultar, recuperar, reutilizar y modificar configuraciones y guardar versiones. Cada entrada identificará qubits, puertas permitidas, profundidad, tolerancia y resultado.

### 7.5 Matriz y Notebook

El menú contextual de U mostrará la matriz del operador correspondiente a la secuencia configurada, calculada en el orden correcto. En móvil, mantener presionada la puerta abrirá el menú. Quantum Notebook reconocerá el cuadrado negro con U y ejecutará la secuencia asociada, no un símbolo vacío.

## 8. Integración entre módulos

| Capacidad | Quantum Open Lab | Quantum Notebook |
|---|---|---|
| Crear puertas teóricas | Crear y programar | Usar las guardadas |
| Editar, eliminar y versionar | Administrar | Reflejar cambios |
| Inventario | Administrar completo | Consultar |
| Matrices | Consultar | Consultar |
| Ejecución teórica | Ejecutar definición | Ejecutar misma definición |
| Investigator | Abrir y explorar | Abrir desde celda |
| Puerta U | Configurar y sintetizar | Reconocer y ejecutar |
| Historial U | Guardar y recuperar | Consultar |

Requisitos transversales: definición común y versionada; persistencia local; compatibilidad entre módulos; manejo de errores y versiones; interfaz adaptable a escritorio y móvil; clic derecho y pulsación prolongada; no romper funciones existentes; Investigador ideal sin ruido; circuito visual, función Python, matriz y ejecución derivados de la misma definición matemática.

## 9. Consideraciones científicas

Una operación unitaria conserva la norma del estado y las relaciones geométricas entre estados. No puede transformar un estado inicial arbitrario en cualquier estado final arbitrario ni clonar estados desconocidos. Las probabilidades de medición en una base no especifican por sí solas un estado completo: las fases relativas pueden ser esenciales. U deberá distinguir entre objetivo de estado, distribución de probabilidades y operador unitario completo.

La esfera de Bloch describe completamente un qubit puro aislado. Para estados reducidos mixtos se usará la matriz de densidad. En sistemas entrelazados, las esferas individuales no sustituyen la descripción del estado global. La síntesis depende del conjunto de puertas, conectividad, número de qubits y límites de recursos; se reportará fidelidad o error.

## 10. Criterios de aceptación

1. Crear puertas arrastrando puertas básicas y mediante Python.
2. Conservar el trabajo al alternar de editor.
3. Guardar localmente y recuperar tras reiniciar.
4. Asignar identificadores únicos y sufijos numéricos.
5. Mostrar las dos últimas puertas y el inventario completo.
6. Arrastrar y ejecutar una puerta como función real.
7. Editar, eliminar y versionar sin sobrescribir la original.
8. Consultar circuito interno y matriz correcta.
9. Reconocer y ejecutar la misma puerta en Notebook.
10. Invocar Investigator desde Open Lab y desde una celda.
11. Avanzar y retroceder sincronizando circuito, estados y cálculos.
12. Mostrar estados reducidos mixtos cuando exista entrelazamiento.
13. Mostrar multiplicaciones y dimensiones correctas.
14. Configurar U mediante estados y probabilidades.
15. Sintetizar sin API de IA y respetar límites.
16. Etiquetar soluciones exactas, aproximadas o no encontradas.
17. Guardar y recuperar el historial U.
18. Verificar que la matriz de U coincide con su secuencia.
19. Ejecutar U desde ambos módulos.
20. Validar interfaz móvil, pulsación prolongada y paneles.
21. Confirmar que los simuladores y sus funciones de ruido siguen funcionando.

## 11. Entregables técnicos recomendados

- Registro y esquema versionado de puertas teóricas.
- Editor visual y editor Python con validación.
- Inventario con persistencia, edición, eliminación y versiones.
- Adaptador de ejecución Python.
- Integración del registro en Quantum Notebook.
- Servicio compartido de cálculo matricial.
- Quantum Circuit Investigator con pasos, snapshots y panel matemático.
- Motor de síntesis interno para U con métricas de error/fidelidad.
- Historial local de objetivos y soluciones U.
- Pruebas unitarias, de integración y de interfaz escritorio/móvil.
- Documentación y guía de uso en inglés dentro de la interfaz.

## 12. Resultado esperado

El usuario podrá diseñar operaciones compuestas con puertas básicas, guardarlas y reutilizarlas en ambos módulos, inspeccionar sus matrices, estudiar visual y matemáticamente la evolución del circuito y utilizar U para sintetizar circuitos que satisfagan objetivos cuánticos. La prioridad será mantener una única definición matemática coherente entre circuito visual, función Python, matriz y ejecución del simulador.
