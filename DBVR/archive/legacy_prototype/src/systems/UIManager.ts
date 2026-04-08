/**
 * UIManager
 * Gestiona la interfaz de usuario en el DOM, específicamente los Toasts / Mensajes
 */

export class UIManager {
  private toastContainer: HTMLElement | null;

  constructor() {
    this.toastContainer = document.getElementById('toastContainer');
  }

  /**
   * Muestra un mensaje emergente en pantalla
   * @param message El texto a mostrar
   * @param durationMs Cuánto tiempo permanecerá visible (milisegundos)
   * @param color Color del texto (ej. '#ffffff')
   * @param borderColor Color del borde (ej. '#00ff88')
   */
  public showToast(
    message: string,
    durationMs: number = 2500,
    color: string = '#ffffff',
    borderColor: string = '#00aa00'
  ): void {
    if (!this.toastContainer) return;

    // Crear elemento
    const toast = document.createElement('div');
    toast.className = 'toast-message';
    toast.innerText = message;
    
    // Aplicar estilos
    toast.style.color = color;
    toast.style.borderColor = borderColor;
    toast.style.boxShadow = `0 4px 15px ${borderColor}66`; // Shadow con borde semitransparente

    // Configurar la animación de salida para que ocurra justo antes del final del timeout
    toast.style.animation = `toastEnter 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards, toastExit 0.3s ease forwards ${durationMs / 1000}s`;

    // Añadir al DOM
    this.toastContainer.appendChild(toast);

    // Limpiar del DOM luego de la duración + animación
    setTimeout(() => {
      if (this.toastContainer && this.toastContainer.contains(toast)) {
        this.toastContainer.removeChild(toast);
      }
    }, durationMs + 350); // +350ms para permitir que termine toastExit
  }
}
