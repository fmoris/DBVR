/**
 * UIManager
 * Gestiona la interfaz de usuario en el DOM, específicamente los Toasts / Mensajes
 * proyectados via WebXR DOM Overlay.
 */

export class UIManager {
  private toastContainer: HTMLElement;

  constructor(parent: HTMLElement) {
    // Buscar o crear el contenedor de toasts dentro del elemento de overlay
    let container = parent.querySelector('#toastContainer') as HTMLElement;
    if (!container) {
      container = document.createElement('div');
      container.id = 'toastContainer';
      container.className = 'toast-container';
      parent.appendChild(container);
    }
    this.toastContainer = container;
  }

  /**
   * Muestra un mensaje emergente en pantalla (proyectado en VR si se usa DOM Overlay)
   * @param message El texto a mostrar (ej. "¡KAMEHAMEHA!")
   * @param durationMs Cuánto tiempo permanecerá visible
   * @param color Color del texto y brillo (ej. '#00eaff')
   * @param borderColor Color del borde (si es distinto del color principal)
   */
  public showToast(
    message: string,
    durationMs: number = 3000,
    color: string = '#ffffff',
    borderColor?: string
  ): void {
    if (!this.toastContainer) return;

    // Crear elemento
    const toast = document.createElement('div');
    toast.className = 'toast-message';
    toast.innerText = message;
    
    // Aplicar estilos dinámicos
    const finalBorderColor = borderColor || color;
    toast.style.color = color;
    toast.style.borderColor = finalBorderColor;
    toast.style.textShadow = `0 0 15px ${color}`;
    toast.style.boxShadow = `0 0 30px ${finalBorderColor}44`; 

    // Duración dinámica en la animación de salida
    const durationSeconds = durationMs / 1000;
    const exitStartTime = Math.max(0.1, durationSeconds - 0.4);
    toast.style.animation = `toastEnter 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards, toastExit 0.4s ease forwards ${exitStartTime}s`;

    // Añadir al DOM
    this.toastContainer.appendChild(toast);

    // Limpiar del DOM luego de la duración + margen para animación de salida
    setTimeout(() => {
      if (this.toastContainer.contains(toast)) {
        this.toastContainer.removeChild(toast);
      }
    }, durationMs + 400); 
  }
}
